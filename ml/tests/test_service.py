import numpy as np
import pytest
from fastapi.testclient import TestClient

from predimaint_ml.features import BASELINE, SPAN, WINDOW
from predimaint_ml.service import app

client = TestClient(app)


def normal(seed, mean, sd, n=SPAN):
    return list(np.round(np.random.default_rng(seed).normal(mean, sd, n), 3))


def machine(drift=0.0):
    s = {"courant": normal(1, 2.0, 0.1), "vibration": normal(2, 10, 3.0), "temperature": normal(3, 40, 0.8)}
    s["vibration"] = s["vibration"][:BASELINE] + [v + drift * 3.0 for v in s["vibration"][BASELINE:]]
    return s


def test_health():
    assert client.get("/health").json()["statut"] == "ok"


def test_normal_machine_low_risk_and_drift_raises_it():
    calme = client.post("/predict", json={"machineId": 1, "series": machine()}).json()
    derive = client.post("/predict", json={"machineId": 1, "series": machine(drift=2.5)}).json()
    assert calme["donneesSuffisantes"] and derive["donneesSuffisantes"]
    assert calme["niveau"] == "FAIBLE"
    assert derive["probabilite"] > 2 * calme["probabilite"]
    assert derive["niveau"] in ("MOYEN", "ELEVE")
    assert derive["facteurs"][0]["canal"] == "vibration"
    assert derive["facteurs"][0]["ecart"] > 2


def test_not_enough_history():
    s = {"vibration": [None] * (SPAN - WINDOW) + [10.0] * WINDOW}
    r = client.post("/predict", json={"series": s}).json()
    assert r["donneesSuffisantes"] is False and r["probabilite"] is None and r["niveau"] == "INCONNU"


@pytest.mark.parametrize("series", [
    {"pression": [1.0] * SPAN},
    {"courant": [1.0] * 10},
    {"courant": ["abc"] * SPAN},
])
def test_invalid_payloads(series):
    assert client.post("/predict", json={"series": series}).status_code == 422


def test_batch_and_api_key(monkeypatch):
    r = client.post("/predict/batch", json=[{"machineId": i, "series": machine()} for i in range(3)])
    assert [x["machineId"] for x in r.json()] == [0, 1, 2]
    monkeypatch.setenv("ML_API_KEY", "secret")
    assert client.post("/predict", json={"series": machine()}).status_code == 401
    assert client.post("/predict", json={"series": machine()}, headers={"X-API-Key": "secret"}).status_code == 200
    assert client.get("/health").status_code == 200  # la sonde de santé reste publique


def test_quiet_real_sensor_noise_is_not_a_drift():
    # cas réel : courant à vide 0.02 A +/- 0.004 A, une pointe à 0.044 A dans les dernières minutes
    rng = np.random.default_rng(7)
    courant = list(np.round(0.02 + rng.normal(0, 0.002, SPAN), 4))
    courant[-3:] = [0.044, 0.040, 0.03]
    temp = list(np.round(24 + rng.normal(0, 0.05, SPAN), 2))
    r = client.post("/predict", json={"series": {"courant": courant, "temperature": temp}}).json()
    assert r["niveau"] == "FAIBLE"
    assert all(abs(f["ecart"]) < 1.5 for f in r["facteurs"])
    # une vraie charge (1.5 A) reste une dérive nette
    courant[-24:] = [1.5] * 24
    r = client.post("/predict", json={"series": {"courant": courant, "temperature": temp}}).json()
    assert r["facteurs"][0]["canal"] == "courant" and r["facteurs"][0]["ecart"] > 10
