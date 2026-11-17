# PrédiMaint

Predictive maintenance for a factory floor. An ESP32 on each machine reads current, vibration, temperature, and humidity every 5 seconds. A backend turns those readings into alerts, machine states, maintenance work, and a probability of failure within 48 hours. Technicians and maintenance managers work from an Android app. The production director steers the plant from a web app.

[![CI](https://github.com/Amine-Dahmen/Predictive_Maintenance/actions/workflows/ci.yml/badge.svg)](https://github.com/Amine-Dahmen/Predictive_Maintenance/actions/workflows/ci.yml)

## What it does

- Collects four measurements per machine over MQTT, with a local LED when a threshold is crossed.
- Raises one open alert per sensor, escalates it to critical, and keeps a live machine state.
- Plans, assigns, reports, and closes interventions, including photos and offline drafts on the phone.
- Scores each machine’s risk of failing in the next 48 hours from how it drifts versus its own recent normal.
- Gives the director availability, MTBF, MTTR, downtime cost, and a printable maintenance report.
- Updates board firmware over the air, with a hash check before any file is replaced and an automatic rollback.

## Architecture

```text
 DHT22 (T, RH) ─┐
 SW-420 (vib.) ─┼─ ESP32 ──Wi-Fi/MQTT──▶ Mosquitto ──▶ Node.js API ──REST + SSE──▶ Flutter (shop floor)
 ACS712 (A)    ─┘     ▲                     ACL            │                              Angular (director)
                       │                                    ├── PostgreSQL
                       └──── thresholds, OTA ◀──────────────┤
                                                            └── every 5 min ──▶ FastAPI (failure risk)
```

| Part | Folder | Stack | Role |
|---|---|---|---|
| Firmware | [`partie_embarque/`](partie_embarque/) | MicroPython, ESP32 | Read sensors every 5 s, publish MQTT, buffer 15 min of Wi-Fi loss, OTA with rollback |
| Broker | [`backend/mosquitto/`](backend/mosquitto/), [`deploy/mosquitto/`](deploy/mosquitto/) | Mosquitto 2 | One account per board, no anonymous access, per-machine ACL |
| API | [`backend/`](backend/) | Node.js 22, Express, PostgreSQL 16 | Measures, alerts, states, interventions, KPIs, reports, archiving |
| Model | [`ml/`](ml/) | Python, scikit-learn, FastAPI | Probability of failure within 48 h |
| Mobile | [`mobile/`](mobile/) | Flutter 3.50 | Technicians and maintenance managers |
| Web | [`frontend/`](frontend/) | Angular 21 | Production director: KPIs, risk, reports, accounts |
| CI | [`.github/`](.github/) | GitHub Actions | Tests, secret scan, SAST, dependency and image scans |

A measurement follows one path. The board publishes `{"courant","vibration","temperature","humidite","ts"}` on `usine/machines/<code>/mesures`. The MQTT username is the machine code, so the ACL stops a board from writing for another machine. The API validates the payload, applies calibration (`gain × raw + offset`), stores one row per sensor, and compares the value with that machine’s thresholds. A breach opens or escalates an alert, the machine state is recomputed, and open apps receive the event on `GET /api/stream`.

Machine state is computed in this order: **EN_MAINTENANCE** (an intervention is in progress), **PANNE** (open curative repair or unclosed critical alert), **ALERTE**, **SANS_DONNEES** (no recent reception, including an MQTT last will of `offline`), otherwise **NORMAL**.

Every 5 minutes the API sends each machine’s last 192 hourly means to the model. Measures older than 90 days are summarised per hour and deleted.

### Who uses which app

| Role | Mobile | Web |
|---|---|---|
| Technician | Alerts, machine sheets, interventions (start, report, photos, close), calibration, offline mode | Release 1 read-only views |
| Maintenance manager | Everything above, plus thresholds, alert closure, planning, technicians, sensor replacement, comparison, firmware | Indicators, reports, machine declaration |
| Production director | Dashboard and responsable accounts | Availability, MTBF/MTTR, downtime cost, failure risk, reports, notification channels |

Field work (Release 2 and 3) lives in the mobile app. The web app is the director’s console, plus the original live views.

## Failure risk

The model estimates **P(failure within 48 hours)**. It is a histogram gradient boosting classifier with isotonic calibration, trained on Microsoft’s synthetic Azure Predictive Maintenance dataset and evaluated on 20 machines it never saw during training.

Features are unit-free and relative to each machine: the last 24 hours compared with that machine’s previous week (z-score, short-window z-score, peak, variability ratio, slope) on current, vibration, and temperature. That is what lets a model trained on volts and pressure be applied to amps, pulses per second, and °C. Humidity is not used. Failures that only show up as a change in rotation speed cannot be anticipated, because the board has no tachometer.

| | ROC-AUC | PR-AUC | Brier |
|---|---|---|---|
| Deployed model (sensors only) | 0.80 | 0.22 | 0.030 |
| Logistic regression, same features | 0.79 | 0.22 | 0.031 |

The positive rate in the training windows is 3.8%, so a PR-AUC of 0.22 is the number to compare with chance (about 0.04). At probability 0.20 the model sees about 73% of failures on the held-out machines, and about 97% of those that show on voltage, pressure, or vibration, with roughly 2.8 false-alarm episodes per machine per month.

Bands in the apps: **FAIBLE** under 0.10, **MOYEN** from 0.10 to 0.20, **ELEVE** at 0.20 and above. The UI asks for an inspection. It does not claim a certain failure.

A variant that also used “hours since last maintenance” reaches 0.98 ROC-AUC and is **not** deployed. On that dataset, components fail on a schedule after replacement, so the model stops looking at the sensors. In this plant, “last maintenance” is any human intervention, and a machine with no recorded maintenance would look risky forever.

Full training notes, the channel mapping, and how to retrain on plant data: [`ml/README.md`](ml/README.md).

## Quick start (Docker)

Requires Docker with the Compose plugin. From the repository root:

```bash
cp .env.example .env
# Replace every secret. Generate two JWT secrets with:
#   node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
# Set PUBLIC_BASE_URL=http://<PC_IP>:3000 if boards will download firmware.

docker compose up -d --build
curl http://localhost:3000/api/health
```

| URL | What |
|---|---|
| http://localhost:8080 | Web app |
| http://localhost:3000/api/docs | OpenAPI |
| `<PC_IP>:1883` | MQTT for the boards |
| `<PC_IP>:3000/api` | Address the mobile app should use |

On first start the API runs the migrations and creates the director account (`SEED_DIRECTEUR_EMAIL` / `SEED_DIRECTEUR_PASSWORD` in `.env`). The password must be changed at first login. MQTT accounts come from `MQTT_MACHINES` (one `CODE:password` per board, the same password as that board’s `credentials.py`).

`docker compose down` keeps the data. `docker compose down -v` deletes it.

Without the ML container the platform still runs. Failure risk is simply absent. The service does not invent a score when it cannot reach the model.

Step-by-step development setup (PostgreSQL, broker, firmware flash, phone install) is in [`docs/ARCHITECTURE_DEPLOIEMENT.md`](docs/ARCHITECTURE_DEPLOIEMENT.md).

## Repository layout

```text
partie_embarque/   ESP32 firmware, host tests, flash script
backend/           REST API, MQTT client, SQL migrations, Mosquitto ACL
ml/                Dataset download, training, model, prediction service
mobile/            Flutter app
frontend/          Angular app
docs/              Deployment, user stories, DevSecOps
deploy/mosquitto/  Broker accounts for Compose
.github/           CI, security scans, image publish
```

## Tests

The same suites run in GitHub Actions on every push and pull request.

| Part | Command |
|---|---|
| API unit | `cd backend && npm test` |
| API integration (real PostgreSQL, wipes the target database) | `cd backend && npm run test:integration` |
| Firmware logic on the PC | `cd partie_embarque && python -m pytest tests_host` |
| Model | `cd ml && python -m pytest` |
| Mobile | `cd mobile && flutter analyze && flutter test` |
| Web | `cd frontend && npx ng test --watch=false` |

## Security

- JWT access tokens (15 min) and rotating refresh tokens stored hashed. Reuse of a refresh token revokes every session. The account is reloaded on each request, so a deactivated user is blocked immediately.
- Role checks and zod validation on every route. SQL is parameterised. Helmet, a CORS allow-list, and login rate limiting.
- MQTT: no anonymous access. A board publishes only on its own topics and reads only its own thresholds and firmware orders.
- Over-the-air updates: SHA-256 checked before any file is replaced, download token hashed and valid for 30 minutes, `credentials.py` and `boot.py` never shipped, rollback after three failed boots.
- Photos are identified from the file bytes (JPEG/PNG), size-limited, and served only to users who can see that intervention.

Production still needs HTTPS in front of the API and the web app, and MQTT over TLS (listener 8883 is prepared in the broker config). Details: [`docs/DEVSECOPS.md`](docs/DEVSECOPS.md) and [`backend/README.md`](backend/README.md).

## Documentation

| Topic | Document |
|---|---|
| Deploy from an empty machine to a working board | [`docs/ARCHITECTURE_DEPLOIEMENT.md`](docs/ARCHITECTURE_DEPLOIEMENT.md) |
| Where each user story lives | [`docs/USER_STORIES.md`](docs/USER_STORIES.md) |
| MQTT topics, payloads, OTA | [`backend/docs/CONTRAT_MQTT.md`](backend/docs/CONTRAT_MQTT.md) |
| REST API and live events | [`backend/docs/API.md`](backend/docs/API.md) |
| Wiring, firmware, Wi-Fi loss | [`partie_embarque/README.md`](partie_embarque/README.md) |
| Model card, training, limits | [`ml/README.md`](ml/README.md) |
| Mobile install and roles | [`mobile/README.md`](mobile/README.md) |
| CI and security loop | [`docs/DEVSECOPS.md`](docs/DEVSECOPS.md) |

## Limits worth stating

The failure model is trained on a **synthetic** public dataset. Scores are a risk to confirm by inspection, and they should be retrained once the plant has its own measures and curative interventions. The backend raises an alert on the first sample over a threshold and a person closes it. The board LED uses hysteresis and clears on its own. Notifications reach open apps and, if SMTP is set, email. Push to a closed phone is not included.
