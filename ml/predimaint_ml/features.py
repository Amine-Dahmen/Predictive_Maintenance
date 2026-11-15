"""Variables d'entrée du modèle, communes à l'entraînement et au service (pas d'écart entraînement / production).

Fenêtre : WINDOW pas de temps récents (24) précédés de BASELINE pas (168) qui servent de référence
« normale » pour CETTE machine. Un pas vaut 1 h en production (moyenne horaire des mesures).

Chaque canal est exprimé en écarts-types par rapport à la référence de la machine : les variables n'ont
pas d'unité, ce qui permet d'appliquer à nos capteurs (A, imp/s, °C) un modèle appris sur le jeu Azure
(V, pression, vibration) :
    courant     <- volt       (canal électrique)
    vibration   <- vibration
    temperature <- pressure   (canal « procédé » : approximation, voir ml/README.md)
"""
import numpy as np
import pandas as pd

WINDOW = 24
BASELINE = 168
SPAN = WINDOW + BASELINE
MIN_BASE = 24      # points de référence valides minimum, sinon variables manquantes (NaN)
MIN_RECENT = 3
MAINT_CAP_H = 90 * 24

# Écart-type minimal de la référence, en unités de NOS capteurs (service uniquement) : en dessous de la
# résolution d'un capteur, une variation n'a pas de sens. Sans ce plancher, un courant à vide qui varie de
# 0.004 A ferait d'un écart de 0.03 A une « dérive » de 10 écarts-types (faux risque élevé). Le jeu Azure
# (tension ~15 V d'écart-type, etc.) n'atteint jamais ces planchers : l'entraînement n'est pas modifié.
SD_FLOOR = {"courant": 0.05, "vibration": 2.0, "temperature": 0.5}

CHANNELS = ("courant", "vibration", "temperature")
AZURE_CHANNELS = {"courant": "volt", "vibration": "vibration", "temperature": "pressure"}
PER_CHANNEL = ("z24", "z6", "zmax6", "sd_ratio", "slope24")
SENSOR_FEATURES = [f"{c}_{f}" for c in CHANNELS for f in PER_CHANNEL]
# Variables du modèle déployé : capteurs seulement. L'ancienneté de la dernière maintenance est très
# prédictive dans le jeu Azure (maintenances planifiées) mais n'a pas le même sens dans notre usine :
# elle est évaluée à part (ablation dans model_card.json) et n'est pas utilisée en production.
FEATURES = SENSOR_FEATURES
FEATURES_WITH_MAINT = SENSOR_FEATURES + ["log_h_maint"]

_T = np.arange(WINDOW, dtype=float)
_TC = _T - _T.mean()
_SXX = float((_TC ** 2).sum())


def channel_features(series, sd_floor=0.0):
    """series : SPAN valeurs (les plus anciennes d'abord), None/NaN autorisés. Renvoie un dict.
    sd_floor : écart-type minimal de la référence (résolution du capteur)."""
    x = np.asarray([np.nan if v is None else v for v in series], dtype=float)
    if x.shape != (SPAN,):
        raise ValueError(f"{SPAN} valeurs attendues, {x.shape[0]} reçues")
    base, recent = x[:BASELINE], x[BASELINE:]
    out = dict.fromkeys(PER_CHANNEL, np.nan)
    nb = np.count_nonzero(~np.isnan(base))
    if nb < MIN_BASE or np.count_nonzero(~np.isnan(recent)) < MIN_RECENT:
        return out
    bm = np.nanmean(base)
    bs = max(np.nanstd(base, ddof=1), sd_floor, 1e-9)
    last6 = recent[-6:]
    out["z24"] = (np.nanmean(recent) - bm) / bs
    out["z6"] = (np.nanmean(last6) - bm) / bs if np.any(~np.isnan(last6)) else np.nan
    out["zmax6"] = (np.nanmax(last6) - bm) / bs if np.any(~np.isnan(last6)) else np.nan
    out["sd_ratio"] = np.nanstd(recent, ddof=1) / bs if np.count_nonzero(~np.isnan(recent)) > 1 else np.nan
    if np.isnan(recent).any():
        ok = ~np.isnan(recent)
        tc = _T[ok] - _T[ok].mean()
        slope = (tc * recent[ok]).sum() / (tc ** 2).sum()
    else:
        slope = (_TC * recent).sum() / _SXX
    out["slope24"] = slope * WINDOW / bs
    return out


def window_features(series_by_channel, hours_since_maintenance=None, sd_floors=None):
    """Variables d'une fenêtre : {canal: SPAN valeurs}, heures depuis la dernière maintenance (None = inconnue).
    sd_floors : {canal: écart-type minimal} (SD_FLOOR pour nos capteurs)."""
    row = {}
    for c in CHANNELS:
        f = channel_features(series_by_channel.get(c) or [None] * SPAN, (sd_floors or {}).get(c, 0.0))
        for k, v in f.items():
            row[f"{c}_{k}"] = v
    h = MAINT_CAP_H if hours_since_maintenance is None else min(max(hours_since_maintenance, 0), MAINT_CAP_H)
    row["log_h_maint"] = np.log1p(h)
    return row


def rolling_features(df, value_col):
    """Version vectorisée de channel_features sur une série horaire régulière (une machine).
    Ligne i = fenêtre se terminant au pas i. Testée contre channel_features (tests/test_features.py)."""
    s = df[value_col].astype(float)
    recent = s.rolling(WINDOW, min_periods=MIN_RECENT)
    base_s = s.shift(WINDOW)
    base = base_s.rolling(BASELINE, min_periods=MIN_BASE)
    bm, bs = base.mean(), base.std(ddof=1).clip(lower=1e-9)
    last6 = s.rolling(6, min_periods=1)
    out = pd.DataFrame(index=df.index)
    out["z24"] = (recent.mean() - bm) / bs
    out["z6"] = (last6.mean() - bm) / bs
    out["zmax6"] = (last6.max() - bm) / bs
    out["sd_ratio"] = recent.std(ddof=1) / bs
    # pente des moindres carrés sur la fenêtre (séries complètes : le jeu Azure n'a pas de trous)
    sty = s.rolling(WINDOW).apply(lambda w: float((_TC * w).sum()), raw=True)
    out["slope24"] = sty / _SXX * WINDOW / bs
    enough = base_s.rolling(BASELINE, min_periods=1).count() >= MIN_BASE
    return out.where(enough)
