# Failure prediction model (US-22, bonus)

The platform estimates, for every machine, the **probability of a failure within the next 48 hours** and
shows it in the mobile app (machine sheet, notification when the risk becomes high) and on the web
(directeur's indicators page). This folder holds the dataset download, the training code, the trained
model and the prediction service.

```
ml/
├── predimaint_ml/
│   ├── download.py   dataset download, every file checked against its git blob SHA-1
│   ├── features.py   input variables, shared by training and serving
│   ├── train.py      dataset construction, training, evaluation, model card
│   └── service.py    FastAPI prediction service (POST /predict, /predict/batch)
├── models/
│   ├── model.joblib     trained model (committed, so the service runs without retraining)
│   └── model_card.json  metrics, thresholds, feature importance, versions
├── tests/            feature consistency, training data, service
├── Dockerfile        service image (python:3.13-slim, non-root, health check)
└── requirements*.txt pinned versions
```

## 1. Dataset

**Microsoft Azure Predictive Maintenance** (from Microsoft's *Predictive Maintenance Modelling Guide*):
100 machines, year 2015, hourly telemetry (`volt`, `rotate`, `pressure`, `vibration`), error log,
maintenance log (component replacements) and **761 failures** of 4 components. It is a **synthetic**
dataset published by Microsoft for teaching predictive maintenance. The original Azure blob storage no
longer exists; `download.py` takes the files from a GitHub mirror and rejects any file whose git blob
SHA-1 differs from the one pinned in the script.

Why this dataset: our boards send a **time series** (current, vibration, temperature, humidity every 5 s),
and this is the public dataset whose sensors and structure are closest (electrical, vibration and process
channels, hourly, many machines, labelled failures). AI4I 2020 (UCI) was considered but it has one
snapshot per product, no history, and no vibration channel.

### What the data shows

Mean of the 24 h window before each failure, in standard deviations from that machine's usual level
(computed during exploration):

| Failed component | Drifting channel | Shift | Our sensor |
|---|---|---|---|
| comp1 | voltage ↑ | +1.3 σ | current (ACS712) |
| comp3 | pressure ↑ | +2.1 σ | temperature (DHT22), used as the "process" channel |
| comp4 | vibration ↑ | +1.8 σ | vibration (SW-420) |
| comp2 | rotation ↓ | −1.5 σ | none (no tachometer on the board): **not observable** |

The drift starts **about 48 h before the failure** (half of it 36 h before, all of it from 24 h before).
That is why the target is "failure within 48 h": with 24 h, half of the clearly abnormal windows were
labelled "no failure".

## 2. Input variables (`features.py`)

A prediction looks at **192 time steps** per channel (1 step = 1 hour in production): the last 24 steps,
and the 168 steps before them (one week) as the machine's **own reference of "normal"**. For each of
the three channels `courant`, `vibration`, `temperature`:

| Variable | Meaning |
|---|---|
| `z24` | mean of the last 24 steps − reference mean, divided by the reference standard deviation |
| `z6` | same for the last 6 steps (fast reaction) |
| `zmax6` | maximum of the last 6 steps, in reference standard deviations |
| `sd_ratio` | variability of the last 24 steps / reference variability |
| `slope24` | trend over the last 24 steps (least squares), in reference standard deviations per window |

Every variable is **unit-free and relative to the machine itself**. That is what lets a model trained on
Azure volts and pressure be applied to our amps, pulses per second and °C, and to machines with a
different normal level. Missing steps (board offline) are allowed: a channel with fewer than 24 reference
points or 3 recent points gives missing values (handled natively by the model), and a machine with less
than one day of history gets "insufficient history" instead of a made-up number.

The same module computes the variables vectorised for training (`rolling_features`) and window by window
in the service (`channel_features`). `tests/test_features.py` checks that both give **identical**
values, which prevents training/serving skew.

## 3. Training (`train.py`)

```bash
cd ml
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m predimaint_ml.download     # 79 MB, verified
.venv/bin/python -m predimaint_ml.train        # ~30 s on a laptop
.venv/bin/python -m pytest
```

- 428,500 windows (one every 2 h per machine, after a week of warm-up), 3.8% labelled "failure within 48 h".
- **Split by machine**: 80 machines for training, **20 machines never seen** for evaluation, because the
  question is how the model behaves on a new machine.
- Model: `HistGradientBoostingClassifier` (scikit-learn), with **isotonic calibration** on folds grouped
  by machine. The app displays a percentage, so the probabilities must mean something.
- Baseline: logistic regression on the same variables.

### Results on the 20 held-out machines (`models/model_card.json`)

| Model | Variables | ROC-AUC | PR-AUC | Brier |
|---|---|---|---|---|
| **Gradient boosting, deployed** | sensors only | **0.80** | **0.22** | 0.030 |
| Logistic regression | sensors only | 0.79 | 0.22 | 0.031 |
| Gradient boosting (not deployed) | sensors + hours since maintenance | 0.98 | 0.74 | 0.016 |

PR-AUC should be compared with the 3.8% positive rate (a random model scores 0.04).

Failures "seen in advance" (probability above the threshold at least once in the 48 h before):

| Threshold | Failures seen | comp1 / comp3 / comp4 (observable) | comp2 | False alarm episodes per machine per month |
|---|---|---|---|---|
| 0.1 (MOYEN, medium risk) | 75% | 97% / 100% / 97% | 28% | 3.3 |
| **0.2 (ELEVE, high risk)** | **73%** | **97% / 100% / 97%** | 23% | **2.8** |
| 0.3 | 33% | 58% / 33% / 42% | 5% | 0.5 |

Risk levels in the app: **FAIBLE** (low) < 0.10 ≤ **MOYEN** (medium) < 0.20 ≤ **ELEVE** (high). A
probability of 0.2 is about 5 times the base rate.

### Why "hours since maintenance" is not used

With it, the model looks excellent (ROC-AUC 0.98), but permutation importance shows that it then relies
almost only on this variable: in the Azure data, components fail on a schedule after their last
replacement. In our factory "last maintenance" means something else (any intervention on the machine,
recorded by people). A machine without recorded maintenance would also sit at the cap and look risky
forever. The deployed model therefore reacts **only to the sensors**. This is the honest choice for a
model transferred from another dataset; the ablation stays in the model card.

### Why the probabilities stay moderate

In this dataset sensor drifts also happen without a following failure (they accompany error events).
A drift therefore means "much higher risk", not "certain failure": the calibrated probability of a
strongly drifting machine is around 0.3 to 0.4 on Azure data. That is why the levels are set at 0.1 and
0.2 and the app speaks of a *risk* and asks for an inspection.

## 4. Deployment

```
ESP32 --MQTT--> backend --(every 5 min) POST /predict/batch--> ML service (FastAPI, :8000)
                   |  192 hourly means per channel and machine         |
                   |<------------- probability, level, main factor ----|
                   +--> table predictions --> SSE prediction.maj / prediction.risque --> mobile, web
```

- **Service**: `uvicorn predimaint_ml.service:app --port 8000`, or the Docker image
  (`docker build -t predimaint-ml ml/`), or the `ml` service of the root `docker-compose.yml`.
  Endpoints: `GET /health`, `GET /modele` (model card), `POST /predict`, `POST /predict/batch`
  (500 machines at most), interactive docs on `/docs`. If `ML_API_KEY` is set, the `X-API-Key` header is
  required (the service is only meant to be called by the backend).
- **Backend** (`backend/src/services/prediction.service.js`): every `PREDICTION_INTERVALLE_S` (300 s)
  it averages each machine's measures per step of `PREDICTION_PAS_S` (3600 s) over the last 192 steps,
  sends one batch to `ML_URL`, stores the results (table `predictions`, 30 days) and publishes
  `prediction.maj`. When a machine **enters** the ELEVE level it publishes `prediction.risque`,
  shown as a notification on the phones. If the service is down, nothing is invented: no row is written
  and a single warning is logged.
- **API**: `GET /api/predictions` (latest per machine), `GET /api/predictions/machines/:id?heures=48`
  (history), `GET /api/predictions/modele`, `POST /api/predictions/executer` (responsable, immediate run).
- **Demo mode**: `PREDICTION_PAS_S=60` compresses time (192 steps = 3 h 12 min instead of 8 days) and
  `npm run demo -- historique M01` writes 191 steps of normal history so the model has a reference at once.
  Then a real drift (shake the machine, warm the DHT22) or `node scripts/simulateur-esp32.js M01 anomalie`.

### End-to-end check (2026-11-12, isolated stack: broker :1884, backend :3100, ML :8100)

1. Demo history plus the simulator in normal mode: **1.4%, FAIBLE**
   (main factor: vibration 0.4 σ above usual).
2. Simulator in drift mode: **82%, ELEVE** (vibration 14 σ above usual).
3. The model raised **ELEVE 9 s before the first threshold alert** (vibration) and 21 to 25 s before the
   current and temperature alerts. In demo time, 1 s ≈ 1 min of real time.

## 5. Seeing the model work: how much data it needs

A prediction needs, per machine, the last **192 steps** of `PREDICTION_PAS_S` seconds. The 24 most recent
steps are what is judged; the 168 before them are the machine's reference "normal". The service answers
**"Historique insuffisant" (INCONNU)** until the reference holds at least 24 steps with data and the
recent window at least 3. Data must therefore go back at least **48 steps** (24 recent + 24 reference).

| Mode | `PREDICTION_PAS_S` | First estimate after | Full window | Use |
|---|---|---|---|---|
| production | 3600 (1 h) | **48 h** of measures | 8 days | real plant |
| demo | 60 (1 min) | **48 min** of measures | 3 h 12 min | presentation, tests |

The backend recomputes every `PREDICTION_INTERVALLE_S` (300 s by default, set 60 in a demo). The result
appears on the mobile machine sheet (risk card with its history, notification when the risk becomes
high) and on the web indicators page (directeur).

**Demo with the real board** (`backend/.env`, then restart the backend):

```
PREDICTION_PAS_S=60
PREDICTION_INTERVALLE_S=60
```

1. Let the board run normally for ~50 minutes; or right away
   `cd backend && npm run demo -- historique M01`, which fills only the empty steps, using the level and noise
   of the machine's real measures of the last 24 h.
2. Machine sheet → card "Panne dans les 48 h : x %": FAIBLE while the machine behaves as usual.
3. Make a channel drift for several minutes: a load through the ACS712, the DHT22 warmed (hand, hair
   dryer) or sustained vibration. The risk rises to MOYEN then ELEVE within a few minutes and names the
   channel. One isolated knock does not: the model looks at the last 6 and 24 steps.
4. Back to production: remove the two lines (or set 3600 / 300) and restart; `npm run demo -- nettoyer`
   removes what `historique` added.

Our sensors are much quieter than the training data (current at rest varies by about 0.004 A). Below a
sensor's resolution a variation means nothing, so the reference standard deviation has a floor in the
service (`SD_FLOOR`: 0.05 A, 2 pulses/s, 0.5 °C). Without it a 0.03 A blip would count as a 10σ drift.
The Azure data never goes below these floors, so training is unchanged.

## 6. Limitations and next steps

- The dataset is **synthetic**: real failures are noisier, so expect lower scores in a real plant.
- `temperature ← pressure` is an approximation (both are slow "process" variables); humidity is not used.
- Failures that only show on rotation speed (comp2) cannot be anticipated with our sensors.
- The board sends vibration as SW-420 pulses per second, a much coarser signal than an accelerometer.
- **Retraining on our own data**: once the plant has a few months of measures and curative interventions,
  label "failure within 48 h" from the start of each curative intervention (`interventions.debut_panne`,
  false alarms excluded) and reuse `features.py` unchanged: only the data loading in `train.py` changes.
