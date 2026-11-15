# Construction du jeu d'entraînement sur un petit jeu synthétique (rapide, sans le vrai jeu Azure).
import numpy as np
import pandas as pd

from predimaint_ml.features import FEATURES
from predimaint_ml.train import HORIZON, build_dataset, event_recall


def fake_azure(hours=24 * 20, fail_at=24 * 15):
    t = pd.date_range("2015-01-01", periods=hours, freq="h")
    rng = np.random.default_rng(0)
    vib = 40 + rng.normal(0, 2, hours)
    vib[fail_at - 40:fail_at] += 8  # dérive de la vibration avant la panne
    tele = pd.DataFrame({"datetime": t, "machineID": 1, "volt": 170 + rng.normal(0, 5, hours),
                         "rotate": 450.0, "pressure": 100 + rng.normal(0, 3, hours), "vibration": vib})
    fail = pd.DataFrame({"datetime": [t[fail_at]], "machineID": [1], "failure": ["comp4"]})
    maint = pd.DataFrame({"datetime": [t[0] - pd.Timedelta(days=30)], "machineID": [1], "comp": ["comp4"]})
    return tele, fail, maint, t[fail_at]


def test_labels_and_features():
    tele, fail, maint, fail_time = fake_azure()
    df = build_dataset(tele, fail, maint)
    assert set(FEATURES) <= set(df.columns)
    pos = df[df.y == 1]
    delta = (fail_time - pos.datetime).dt.total_seconds() / 3600
    assert len(pos) and delta.min() > 0 and delta.max() <= HORIZON
    # la dérive est visible : z-score vibration plus élevé juste avant la panne qu'en régime normal
    assert pos.vibration_z24.mean() > 1.5 > df[df.y == 0].vibration_z24.abs().mean()
    rec, by_comp, n = event_recall(df, np.where(df.y == 1, 0.9, 0.0), 0.5)
    assert rec == 1.0 and n == 1 and by_comp == {"comp4": 1.0}
