"""Service de prédiction (US-22) : POST /predict reçoit les moyennes horaires d'une machine et renvoie la
probabilité de panne dans les 48 h, le niveau de risque et le canal qui s'écarte le plus de l'habitude.

    uvicorn predimaint_ml.service:app --host 0.0.0.0 --port 8000

Variables d'environnement : MODEL_PATH (models/model.joblib), ML_API_KEY (si définie, l'en-tête
X-API-Key est exigé : le service n'est appelé que par le backend).
"""
import json
import math
import os
import secrets
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field, field_validator

from .features import CHANNELS, SD_FLOOR, SPAN, window_features

ROOT = Path(__file__).resolve().parent.parent
MODEL_PATH = Path(os.environ.get("MODEL_PATH", ROOT / "models" / "model.joblib"))
CARD_PATH = MODEL_PATH.with_name("model_card.json")

_bundle = joblib.load(MODEL_PATH)
MODEL, FEATURE_NAMES, VERSION = _bundle["model"], _bundle["features"], _bundle["version"]
CARD = json.loads(CARD_PATH.read_text()) if CARD_PATH.exists() else {}
LEVELS = (0.1, 0.2)  # MOYEN, ELEVE : mêmes valeurs que train.LEVEL_THRESHOLDS
LABELS = {"courant": "Courant", "vibration": "Vibration", "temperature": "Température"}

app = FastAPI(title="PrédiMaint — prédiction de panne", version=VERSION, docs_url="/docs")


def check_key(x_api_key: str | None = Header(default=None)):
    expected = os.environ.get("ML_API_KEY")
    if expected and not (x_api_key and secrets.compare_digest(x_api_key, expected)):
        raise HTTPException(status_code=401, detail="Clé d'API invalide")


Series = list[float | None]


class PredictRequest(BaseModel):
    machineId: int | None = None
    series: dict[str, Series] = Field(description=f"{SPAN} moyennes horaires par canal, les plus anciennes d'abord")

    @field_validator("series")
    @classmethod
    def _check(cls, v):
        for name, values in v.items():
            if name not in CHANNELS:
                raise ValueError(f"canal inconnu : {name} (attendus : {', '.join(CHANNELS)})")
            if len(values) != SPAN:
                raise ValueError(f"{name} : {SPAN} valeurs attendues, {len(values)} reçues")
            if any(x is not None and not math.isfinite(x) for x in values):
                raise ValueError(f"{name} : valeurs non finies")
        return v


class Factor(BaseModel):
    canal: str
    ecart: float = Field(description="écart de la moyenne des 24 derniers pas à l'habitude, en écarts-types")
    libelle: str


class PredictResponse(BaseModel):
    machineId: int | None
    probabilite: float | None
    niveau: str
    donneesSuffisantes: bool
    facteurs: list[Factor]
    modele: str


def level(p):
    if p is None:
        return "INCONNU"
    return "ELEVE" if p >= LEVELS[1] else "MOYEN" if p >= LEVELS[0] else "FAIBLE"


def predict_one(req: PredictRequest) -> PredictResponse:
    row = window_features(req.series, sd_floors=SD_FLOOR)
    factors = []
    for c in CHANNELS:
        z = row[f"{c}_z24"]
        if z is not None and not np.isnan(z):
            sign = "au-dessus" if z > 0 else "en dessous"
            factors.append(Factor(canal=c, ecart=round(float(z), 2),
                                  libelle=f"{LABELS[c]} {abs(z):.1f} écart(s)-type(s) {sign} de l'habitude"))
    factors.sort(key=lambda f: -abs(f.ecart))
    if not factors:  # moins d'une journée d'historique : pas de référence « normale » pour cette machine
        return PredictResponse(machineId=req.machineId, probabilite=None, niveau="INCONNU",
                               donneesSuffisantes=False, facteurs=[], modele=VERSION)
    X = pd.DataFrame([row])[FEATURE_NAMES]
    p = float(MODEL.predict_proba(X)[0, 1])
    return PredictResponse(machineId=req.machineId, probabilite=round(p, 4), niveau=level(p),
                           donneesSuffisantes=True, facteurs=factors[:3], modele=VERSION)


@app.get("/health")
def health():
    return {"statut": "ok", "modele": VERSION}


@app.get("/modele", dependencies=[Depends(check_key)])
def model_card():
    return {**CARD, "niveaux_seuils": {"MOYEN": LEVELS[0], "ELEVE": LEVELS[1]}, "points_par_canal": SPAN}


@app.post("/predict", response_model=PredictResponse, dependencies=[Depends(check_key)])
def predict(req: PredictRequest):
    return predict_one(req)


@app.post("/predict/batch", response_model=list[PredictResponse], dependencies=[Depends(check_key)])
def predict_batch(reqs: list[PredictRequest]):
    if len(reqs) > 500:
        raise HTTPException(status_code=413, detail="500 machines maximum par appel")
    return [predict_one(r) for r in reqs]
