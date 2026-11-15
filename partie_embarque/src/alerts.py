# Threshold alerts on the device.
#
# Each metric has a rule (min, max, hysteresis, confirm). An alert is raised
# after `confirm` consecutive out-of-range values, and cleared only once the
# value is back inside the range by `hysteresis`, so a value hovering around
# the limit doesn't flood the broker with raise/clear messages.
#
# Pure Python (no machine module) so it also runs on the PC for unit tests.


class ThresholdRule:
    def __init__(self, metric, lo, hi, hysteresis=0.0, confirm=1):
        self.metric = metric
        self.lo = lo
        self.hi = hi
        self.hysteresis = hysteresis
        self.confirm = max(1, confirm)
        self.active = False
        self.kind = None      # "high" or "low" while active
        self.count = 0

    def _out_of_range(self, value):
        if self.hi is not None and value > self.hi:
            return "high"
        if self.lo is not None and value < self.lo:
            return "low"
        return None

    def update(self, value):
        """Feed a new value. Returns an event dict on raise/clear, else None."""
        if value is None:
            return None
        if not self.active:
            kind = self._out_of_range(value)
            if kind is None:
                self.count = 0
                return None
            self.count += 1
            if self.count < self.confirm:
                return None
            self.active = True
            self.kind = kind
            return self._event("raised", value)
        limit = self.hi if self.kind == "high" else self.lo
        if self.kind == "high":
            back = value <= limit - self.hysteresis
        else:
            back = value >= limit + self.hysteresis
        if not back:
            return None
        event = self._event("cleared", value)
        self.active = False
        self.kind = None
        self.count = 0
        return event

    def _event(self, state, value):
        return {
            "metric": self.metric,
            "state": state,
            "kind": self.kind,
            "value": value,
            "limit": self.hi if self.kind == "high" else self.lo,
        }


class AlertMonitor:
    def __init__(self, thresholds):
        """thresholds: {metric: (min, max, hysteresis, confirm)}"""
        self.rules = {}
        for metric, (lo, hi, hyst, confirm) in thresholds.items():
            self.rules[metric] = ThresholdRule(metric, lo, hi, hyst, confirm)

    def check(self, values):
        """values: {metric: value}. Returns the list of raise/clear events."""
        events = []
        for metric, rule in self.rules.items():
            event = rule.update(values.get(metric))
            if event:
                events.append(event)
        return events

    def active(self):
        return [m for m, r in self.rules.items() if r.active]

    def set_limits(self, seuils):
        """Apply the thresholds sent by the backend (US-11).

        seuils: {metric: {"alerte": a, "critique": c}} -> the local rule alerts
        above the "alerte" level. Metrics without a local rule get one, with a
        hysteresis of 5 % of the limit and 2 confirmations.
        """
        changed = []
        for metric, s in seuils.items():
            hi = s.get("alerte")
            if not isinstance(hi, (int, float)):
                continue
            rule = self.rules.get(metric)
            if rule is None:
                self.rules[metric] = ThresholdRule(metric, None, hi, abs(hi) * 0.05, 2)
            elif rule.hi == hi:
                continue
            else:
                rule.hi = hi
            changed.append(metric)
        return changed
