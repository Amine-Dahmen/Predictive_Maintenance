# Host-side unit tests for the firmware alert logic (src/alerts.py).
# Run on the PC: python -m pytest tests_host
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from alerts import AlertMonitor, ThresholdRule  # noqa: E402


def feed(rule, values):
    return [rule.update(v) for v in values]


def test_raise_needs_confirm_consecutive_values():
    rule = ThresholdRule("temperature", None, 45.0, 1.0, confirm=2)
    events = feed(rule, [46, 44, 46, 47])
    assert events[:3] == [None, None, None]
    assert events[3]["state"] == "raised"
    assert events[3]["kind"] == "high"
    assert events[3]["limit"] == 45.0


def test_hysteresis_on_clear():
    rule = ThresholdRule("temperature", None, 45.0, 1.0, confirm=1)
    assert rule.update(46)["state"] == "raised"
    assert rule.update(44.5) is None          # inside, but not by the hysteresis margin
    assert rule.update(46) is None            # still active, no duplicate raise
    ev = rule.update(43.9)
    assert ev["state"] == "cleared" and ev["kind"] == "high"
    assert not rule.active


def test_low_limit():
    rule = ThresholdRule("humidity", 20.0, None, 2.0, confirm=1)
    assert rule.update(25) is None
    assert rule.update(19)["kind"] == "low"
    assert rule.update(21) is None
    assert rule.update(22)["state"] == "cleared"


def test_missing_value_is_ignored():
    rule = ThresholdRule("temperature", None, 45.0, 1.0, confirm=2)
    assert feed(rule, [46, None, 46])[2]["state"] == "raised"


def test_monitor_tracks_active_metrics():
    mon = AlertMonitor({
        "temperature": (None, 45.0, 1.0, 1),
        "vibration": (None, 20.0, 5.0, 1),
    })
    events = mon.check({"temperature": 50, "vibration": 3, "humidity": 99})
    assert [e["metric"] for e in events] == ["temperature"]
    assert mon.active() == ["temperature"]
    events = mon.check({"temperature": 30, "vibration": 30})
    assert {(e["metric"], e["state"]) for e in events} == {
        ("temperature", "cleared"), ("vibration", "raised")}
    assert mon.active() == ["vibration"]


def test_limits_from_the_application():
    mon = AlertMonitor({"temperature": (None, 45.0, 1.0, 1)})
    changed = mon.set_limits({"temperature": {"alerte": 30, "critique": 40},
                              "courant": {"alerte": 2.5, "critique": 4},
                              "humidite": {"alerte": None}})
    assert sorted(changed) == ["courant", "temperature"]
    assert mon.rules["temperature"].hi == 30
    assert mon.rules["courant"].hi == 2.5
    assert mon.set_limits({"temperature": {"alerte": 30}}) == []   # unchanged
    events = mon.check({"temperature": 35})
    assert events[0]["limit"] == 30
