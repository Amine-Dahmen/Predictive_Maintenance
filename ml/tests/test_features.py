# Les variables calculées à l'entraînement (vectorisé) et en service (une fenêtre) doivent être identiques.
import numpy as np
import pandas as pd
import pytest

from predimaint_ml.features import BASELINE, CHANNELS, SPAN, WINDOW, channel_features, rolling_features, window_features


def series(n=400, seed=0):
    rng = np.random.default_rng(seed)
    return pd.DataFrame({"v": 100 + rng.normal(0, 5, n)})


def test_rolling_equals_single_window():
    df = series()
    roll = rolling_features(df, "v")
    for end in (SPAN - 1, 250, 399):
        single = channel_features(df.v.iloc[end - SPAN + 1:end + 1].tolist())
        for k, v in single.items():
            assert roll[k].iloc[end] == pytest.approx(v, rel=1e-9, abs=1e-9), k


def test_drift_is_measured_in_machine_standard_deviations():
    base = list(100 + np.random.default_rng(1).normal(0, 5, BASELINE))
    drifted = base + [115.0] * WINDOW           # +15 = +3 écarts-types
    f = channel_features(drifted)
    assert f["z24"] == pytest.approx(3, abs=0.6)
    # les unités n'ont pas d'importance : x1000 donne les mêmes variables
    g = channel_features([v * 1000 for v in drifted])
    assert g["z24"] == pytest.approx(f["z24"])


def test_missing_values_and_short_history():
    vals = [None] * (BASELINE - 10) + [1.0] * 10 + [1.0] * WINDOW
    assert np.isnan(channel_features(vals)["z24"])          # pas assez de référence
    vals = [1.0 + (i % 3) for i in range(BASELINE)] + [None] * 20 + [2.0] * 4
    assert not np.isnan(channel_features(vals)["slope24"])  # trous tolérés dans la fenêtre récente
    with pytest.raises(ValueError):
        channel_features([1.0] * 10)


def test_window_features_has_every_channel():
    row = window_features({"courant": [1.0] * SPAN})
    assert set(k.split("_")[0] for k in row if k != "log_h_maint") == set(CHANNELS)
    assert np.isnan(row["vibration_z24"])
