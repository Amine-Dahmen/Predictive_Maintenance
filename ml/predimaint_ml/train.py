"""Entraînement du modèle de probabilité de panne (US-22).

    python -m predimaint_ml.train [--data data/raw] [--out models]

Cible : « une panne survient dans les HORIZON prochaines heures » (48 h), à partir de la fenêtre de
mesures qui se termine à l'instant t. Évaluation sur 20 machines jamais vues à l'entraînement.
Produit models/model.joblib et models/model_card.json (métriques, seuils, version).
"""
import argparse
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.calibration import CalibratedClassifierCV
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score
from sklearn.model_selection import GroupKFold, GroupShuffleSplit
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

from .features import (AZURE_CHANNELS, CHANNELS, FEATURES, FEATURES_WITH_MAINT, MAINT_CAP_H, PER_CHANNEL, SPAN,
                       rolling_features)

HORIZON = 48  # la dérive des capteurs commence ~48 h avant la panne dans ce jeu (voir ml/README.md)
STEP = 2            # une ligne toutes les 2 h (les lignes voisines sont presque identiques)
SEED = 42
# Seuils des niveaux de risque (MOYEN, ELEVE), choisis sur le compromis détection / fausses alertes du jeu de
# test (voir model_card.json « seuils »). Une probabilité de 0.2 vaut ~5 fois le taux de base.
LEVEL_THRESHOLDS = (0.1, 0.2)
VERSION = "pdm-azure-hgb-48h-1"


def load(data_dir):
    d = Path(data_dir)
    tele = pd.read_csv(d / "PdM_telemetry.csv", parse_dates=["datetime"])
    fail = pd.read_csv(d / "PdM_failures.csv", parse_dates=["datetime"])
    maint = pd.read_csv(d / "PdM_maint.csv", parse_dates=["datetime"])
    return tele, fail, maint


def build_dataset(tele, fail, maint):
    rows = []
    for mid, g in tele.sort_values("datetime").groupby("machineID"):
        g = g.set_index("datetime").asfreq("h").reset_index()  # série horaire régulière
        feats = pd.DataFrame({"datetime": g["datetime"], "machineID": mid})
        for c in CHANNELS:
            f = rolling_features(g, AZURE_CHANNELS[c])
            for k in PER_CHANNEL:
                feats[f"{c}_{k}"] = f[k].to_numpy()
        # heures depuis la dernière maintenance (toute composante), avant l'instant t
        m = maint.loc[maint.machineID == mid, ["datetime"]].sort_values("datetime").rename(columns={"datetime": "last_maint"})
        feats = pd.merge_asof(feats, m, left_on="datetime", right_on="last_maint", direction="backward",
                              allow_exact_matches=False)
        h = (feats["datetime"] - feats["last_maint"]).dt.total_seconds() / 3600
        feats["log_h_maint"] = np.log1p(h.fillna(MAINT_CAP_H).clip(0, MAINT_CAP_H))
        # étiquette : prochaine panne dans ]t, t + HORIZON]
        fm = fail.loc[fail.machineID == mid, ["datetime", "failure"]].sort_values("datetime").rename(
            columns={"datetime": "next_fail", "failure": "next_comp"})
        feats = pd.merge_asof(feats, fm, left_on="datetime", right_on="next_fail", direction="forward",
                              allow_exact_matches=False)
        delta = (feats["next_fail"] - feats["datetime"]).dt.total_seconds() / 3600
        feats["y"] = (delta <= HORIZON).astype(int)
        feats = feats.iloc[SPAN - 1::STEP]
        rows.append(feats)
    df = pd.concat(rows, ignore_index=True)
    return df.dropna(subset=[f"{CHANNELS[0]}_z24"])


def models():
    hgb = HistGradientBoostingClassifier(max_iter=300, learning_rate=0.05, max_leaf_nodes=31,
                                         l2_regularization=1.0, class_weight=None, random_state=SEED)
    logreg = make_pipeline(SimpleImputer(), StandardScaler(), LogisticRegression(max_iter=2000, class_weight="balanced"))
    return {"hgb": hgb, "logreg": logreg}


def event_recall(test, proba, threshold):
    """Part des pannes « vues » : probabilité >= seuil au moins une fois dans les HORIZON heures qui précèdent."""
    t = test.assign(p=proba)
    pos = t[t.y == 1]
    seen = pos.groupby(["machineID", "next_fail", "next_comp"]).p.max() >= threshold
    by_comp = seen.groupby(level="next_comp").mean().round(3).to_dict()
    return float(seen.mean()), by_comp, int(seen.size)


def false_alarms_per_machine_month(test, proba, threshold):
    """Fenêtres « à risque » sans panne dans les 24 h, ramenées à une machine et 30 jours
    (une ligne = 2 h ; des lignes consécutives au-dessus du seuil comptent pour une seule fausse alerte)."""
    t = test.assign(a=(proba >= threshold) & (test.y == 0)).sort_values(["machineID", "datetime"])
    starts = t.a & ~t.groupby("machineID").a.shift(fill_value=False)
    months = t.groupby("machineID").datetime.agg(lambda s: (s.max() - s.min()).total_seconds() / (30 * 86400)).sum()
    return float(starts.sum() / months)


def main():
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--data", default=root / "data" / "raw")
    ap.add_argument("--out", default=root / "models")
    args = ap.parse_args()
    t0 = time.time()

    tele, fail, maint = load(args.data)
    df = build_dataset(tele, fail, maint)
    print(f"jeu d'entraînement : {len(df)} fenêtres, {df.y.mean():.2%} positives, {df.machineID.nunique()} machines "
          f"({time.time() - t0:.0f} s)")

    split = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=SEED)
    tr_idx, te_idx = next(split.split(df, df.y, df.machineID))
    train, test = df.iloc[tr_idx], df.iloc[te_idx]
    y_tr, y_te = train.y, test.y

    results = {}
    fitted = {}
    candidates = [("hgb", FEATURES), ("logreg", FEATURES), ("hgb+maintenance", FEATURES_WITH_MAINT)]
    for name, cols in candidates:
        base = models()[name.split("+")[0]]
        X_tr, X_te = train[cols], test[cols]
        # calibration isotonique avec des plis par machine : les probabilités sont fiables (US-22 affiche un %)
        folds = list(GroupKFold(n_splits=3).split(X_tr, y_tr, train.machineID))
        clf = CalibratedClassifierCV(base, method="isotonic", cv=folds)
        clf.fit(X_tr, y_tr)
        p = clf.predict_proba(X_te)[:, 1]
        results[name] = {"roc_auc": roc_auc_score(y_te, p), "pr_auc": average_precision_score(y_te, p),
                         "brier": brier_score_loss(y_te, p)}
        fitted[name] = (clf, p)
        print(f"{name:16s} ROC-AUC {results[name]['roc_auc']:.3f}  PR-AUC {results[name]['pr_auc']:.3f}  "
              f"Brier {results[name]['brier']:.4f}")

    model, p = fitted["hgb"]
    thresholds = {}
    for thr in LEVEL_THRESHOLDS + (0.3, 0.5):
        rec, by_comp, n = event_recall(test, p, thr)
        fa = false_alarms_per_machine_month(test, p, thr)
        thresholds[str(thr)] = {"pannes_detectees": round(rec, 3), "par_composant": by_comp,
                                "fausses_alertes_par_machine_mois": round(fa, 2)}
        print(f"seuil {thr}: {rec:.1%} des {n} pannes vues avant ({by_comp}), "
              f"{fa:.2f} fausse(s) alerte(s) / machine / mois")

    # Importance des variables (permutation sur le jeu de test, ROC-AUC)
    from sklearn.inspection import permutation_importance
    sample = test.sample(min(len(test), 20000), random_state=SEED)
    imp = permutation_importance(model, sample[FEATURES], sample.y, scoring="roc_auc", n_repeats=3, random_state=SEED)
    importance = sorted(zip(FEATURES, imp.importances_mean), key=lambda x: -x[1])

    # Modèle final : toutes les machines
    folds = list(GroupKFold(n_splits=3).split(df[FEATURES], df.y, df.machineID))
    final = CalibratedClassifierCV(models()["hgb"], method="isotonic", cv=folds)
    final.fit(df[FEATURES], df.y)

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    joblib.dump({"model": final, "features": FEATURES, "version": VERSION}, out / "model.joblib", compress=3)
    card = {
        "version": VERSION,
        "entraine_le": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "jeu_de_donnees": "Microsoft Azure Predictive Maintenance (100 machines, 2015, télémesures horaires)",
        "cible": f"panne dans les {HORIZON} h",
        "fenetre": {"recente_h": 24, "reference_h": 168},
        "correspondance_canaux": AZURE_CHANNELS,
        "fenetres": int(len(df)), "taux_positifs": round(float(df.y.mean()), 4),
        "evaluation": "20 machines jamais vues (GroupShuffleSplit), probabilités calibrées (isotonique)",
        "metriques_test": {k: {m: round(v, 4) for m, v in r.items()} for k, r in results.items()},
        "seuils": thresholds,
        "niveaux": {"FAIBLE": f"< {LEVEL_THRESHOLDS[0]}", "MOYEN": f"{LEVEL_THRESHOLDS[0]} à {LEVEL_THRESHOLDS[1]}",
                    "ELEVE": f">= {LEVEL_THRESHOLDS[1]}"},
        "taux_de_base": round(float(df.y.mean()), 4),
        "importance_variables": [{"variable": f, "importance": round(float(v), 4)} for f, v in importance[:10]],
        "duree_s": round(time.time() - t0),
        "sklearn": __import__("sklearn").__version__,
    }
    (out / "model_card.json").write_text(json.dumps(card, indent=2, ensure_ascii=False))
    print(f"modèle écrit dans {out} ({time.time() - t0:.0f} s)")


if __name__ == "__main__":
    main()
