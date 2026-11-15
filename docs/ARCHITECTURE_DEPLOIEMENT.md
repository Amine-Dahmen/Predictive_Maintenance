# PrédiMaint — architecture and deployment

State of the project after **Release 3 and the failure prediction model** (November 2026). This document
explains how the pieces fit together and how to start everything, in order, from an empty PC to a working
system: sensors → ESP32 → MQTT → backend (+ AI) → mobile app and web app.

Detailed references:

| Topic | Document |
|---|---|
| How each user story is implemented | [`USER_STORIES.md`](USER_STORIES.md) |
| AI model: dataset, training, results, deployment | [`../ml/README.md`](../ml/README.md) |
| CI / security loop | [`DEVSECOPS.md`](DEVSECOPS.md) |
| Firmware and wiring | [`../partie_embarque/README.md`](../partie_embarque/README.md) |
| MQTT contract (topics, messages, OTA) | [`../backend/docs/CONTRAT_MQTT.md`](../backend/docs/CONTRAT_MQTT.md) |
| REST API and real-time events | [`../backend/docs/API.md`](../backend/docs/API.md), Swagger at `http://<PC_IP>:3000/api/docs` |
| Mobile app | [`../mobile/README.md`](../mobile/README.md) |

## 1. Architecture

```
 Machine                    PC / server (same LAN as the boards)                                  Users
┌─────────────────┐       ┌──────────────────────────────────────────────────────────────┐
│ DHT22  (T, RH)  │       │ Mosquitto :1883      Node.js backend :3000                    │   ┌─────────────────┐
│ SW-420 (vibr.)  ├ESP32──┼▶ .../mesures  ─────▶ MQTT client ─▶ thresholds ─▶ alerts      │   │ Flutter app     │
│ ACS712 (current)│ Wi-Fi │  .../statut          │   calibration   machine states        ├──▶│ (Android)       │
│ LED (GPIO2)     │◀──────┼─ .../config (thresholds)                                      │   │ technicien      │
│ boot.py / ota.py│◀──────┼─ .../ota  (firmware update order)       REST /api + SSE ──────┼──▶│ responsable     │
└─────────────────┘ HTTP  │                       │                 /api/stream            │   │ (directeur)     │
        ▲  download ──────┼── /api/firmware/telechargement/<token>   │                    │   └─────────────────┘
        │  (US-46)        │      PostgreSQL :5432  ◀───┘              │                    │   ┌─────────────────┐
        │                 │   measures, hourly archive, alerts,       ├───────────────────┼──▶│ Angular web app │
        │                 │   interventions, photos, predictions      │ every 5 min        │   │ :4200 / :8080   │
        │                 │                       ML service :8000 ◀──┘ POST /predict/batch│   │ directeur       │
        │                 │                       (FastAPI, model)                         │   │ (KPIs, reports, │
        │                 └──────────────────────────────────────────────────────────────┘   │  admin)         │
                                                                                               └─────────────────┘
```

| Part | Folder | Technology | Role |
|---|---|---|---|
| Firmware | `partie_embarque/` | MicroPython 1.29, ESP32 | reads the 3 sensors every 5 s, publishes over MQTT, LED on local thresholds, buffers during Wi-Fi loss, remote update with rollback |
| Broker | `backend/mosquitto/`, `deploy/mosquitto/` | Mosquitto 2 | one account per board + backend, per-machine ACL |
| Backend | `backend/` | Node.js 22, Express, PostgreSQL, `mqtt`, JWT | measures, calibration, thresholds and alerts, machine states, interventions and photos, KPIs and reports, archiving, notification channels, OTA, calls the ML service, REST + SSE |
| ML service | `ml/` | Python 3.13, scikit-learn, FastAPI | probability of failure within 48 h per machine |
| Mobile app | `mobile/` | Flutter 3.50 (Android) | **Release 2 and 3 field work**: technicians and maintenance managers (alerts, machines, interventions, photos, offline mode, calibration, comparison, firmware…) |
| Web app | `frontend/` | Angular 21 | **Directeur**: indicators, downtime costs, reports, failure risk, account administration, notification channels (plus the Release 1 views) |
| CI/CD | `.github/` | GitHub Actions | tests, security scans, images (see `DEVSECOPS.md`) |

### Which app for whom

Release 2 is the mobile release. Every Release 2 feature is in the mobile app only, and the web app keeps
Release 1 plus the directeur's Release 3 pages.

| Role | Mobile app | Web app |
|---|---|---|
| Technicien | alerts, machine sheets, calibration, failure declaration, "Mes interventions" (start, report, photos, close), offline mode | Release 1 read-only views |
| Responsable de maintenance | everything above + thresholds, alert closure / false alarms, planning and assignment, technicians (incl. password reset), sensor replacement, machine comparison, firmware updates | indicators, reports, Release 1 views, machine declaration |
| Directeur de production | dashboard, responsables | indicators (availability, MTBF/MTTR, downtime cost, failure evolution), failure risk (AI), reports, responsables (incl. password reset), notification channels |

### Data flow of one measurement

1. Every 5 s the ESP32 publishes `{"courant", "vibration", "temperature", "humidite", "ts"}` on
   `usine/machines/<code>/mesures` (QoS 1). The MQTT username is the machine code, so the ACL stops a board
   from writing for another machine.
2. The backend validates the message, applies the sensor calibration (`gain × raw + offset`, US-39) and
   stores one row per measure.
3. It compares each value with the machine's thresholds. Above a threshold it creates an alert (one open
   alert per sensor, escalated to CRITIQUE), recomputes the machine state and pushes `mesure.recue`,
   `alerte.creee`, `machine.etat` on the SSE stream. `alerte.creee` carries `notifier`, set from the
   notification channels (US-38), and an e-mail may be sent.
4. Every 5 minutes the backend sends each machine's last 192 hourly means to the ML service and publishes
   `prediction.maj`. A machine entering the high-risk level triggers `prediction.risque` (US-22).
5. Measures older than 90 days are summarised per hour and deleted (US-40).
6. Thresholds changed in the app go back to the board on `.../config` (retained); a firmware update order
   goes on `.../ota` (US-46).
7. When a board disconnects, the broker publishes its last will (`offline`) and the machine turns grey.
   Measurements taken during a Wi-Fi outage are replayed with their original timestamps.

## 2. Network: what to change when you change network

The boards, the PC and the phones must reach each other: same Wi-Fi/LAN, or a phone connected over USB
(see §5.3). Find the PC address with `ip -4 addr` (Linux) or `ipconfig` (Windows); below it is
`<PC_IP>`.

| Port | Service | Who connects |
|---|---|---|
| 1883 | Mosquitto (MQTT) | ESP32 boards, backend |
| 3000 | backend REST API + SSE, firmware downloads | apps, boards (OTA) |
| 4200 / 8080 | web app (dev server / Docker) | browsers |
| 8000 | ML service | backend only |
| 5432 | PostgreSQL | backend only |

Open 1883 and 3000 (and 4200/8080) in the firewall if one is active (`sudo ufw allow 1883,3000,4200,8080/tcp`).

**When you move to another network** (for example from home to the network used for the demo), only
these values change:

| Where | What |
|---|---|
| `partie_embarque/src/credentials.py` | `WIFI_SSID`, `WIFI_PASSWORD`, `MQTT_HOST = "<PC_IP>"`, then `./esp.sh deploy` |
| `backend/.env` | `PUBLIC_BASE_URL=http://<PC_IP>:3000` (OTA downloads; auto-detected if empty), `CORS_ORIGINS` (add `http://<PC_IP>:4200`) |
| mobile app | **nothing to rebuild**: login screen → "Serveur : …" → Modifier → type the new `<PC_IP>` → Tester → Enregistrer (saved on the phone) |

**Project setup: the phone is the hotspot.** The PC and the ESP32 join the phone's hotspot (network
"BHK"). The phone may stay connected to another Wi-Fi at the same time (Wi-Fi sharing). The phone
reaches the PC at the address its hotspot gave the PC: on 2026-11-13 that was **192.168.45.116** (the
phone itself was 192.168.45.117, the gateway). This is the app's default server and the `MQTT_HOST` of
`credentials.py`. If the PC gets another address after reconnecting (`ip -4 addr`, look at the `inet` line of
`wlo1`), change it in two places: the app's "Serveur" field and `MQTT_HOST` in `credentials.py`
(`./esp.sh deploy`). Then check from the phone's browser that `http://<PC_IP>:3000/api/health` answers.

**Keep the PC clock right (NTP).** The board stamps its measures with NTP time. On 2026-11-13 the PC was one
hour fast ("System clock synchronized: no", which is typical of a dual boot with Windows). The backend now
copes with it: sensor presence uses reception time, and timestamps more than 20 min off are replaced by
server time with a warning in the log. All dates are still an hour off, though. Fix the PC once:
`sudo timedatectl set-ntp true`. With a Windows dual boot, also make Windows keep the hardware clock in UTC
(registry `HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation\RealTimeIsUniversal` = 1, DWORD).
Check it with `timedatectl` ("System clock synchronized: yes").

Nothing else depends on the network. The PC's address is never committed: real values go in
`credentials.py` and `.env`, which git ignores. Keep `credentials_example.py` with placeholders, because
the CI secret scan blocks real passwords.

> On the development PC a system Mosquitto may already listen on 1883 with anonymous access. Stop it
> (`sudo systemctl disable --now mosquitto`) or run the project broker on another port
> (`MQTT_PORT=1884 npm run mqtt:linux`) and use that port everywhere.

## 3. Hardware

| Sensor | Sensor pin → ESP32 pin |
|---|---|
| DHT22 (temperature, humidity) | VCC → 3V3, DATA → **GPIO21** (4.7k–10k pull-up), GND → GND |
| SW-420 (vibration) | VCC → **3V3** (not 5V), DO → **GPIO19**, GND → GND |
| ACS712 (current) | VCC → **5V/VIN**, OUT → **10k/20k divider** → **GPIO34**, GND → GND, IP+/IP− in series with the load |
| Alert LED | on-board, GPIO2 |

```
ACS712 OUT ──[10k]──┬──[20k]── GND        all grounds common
                    └── GPIO34
```

Never connect the ACS712 output directly to the ESP32: it can reach ~4.5 V. At boot no current may flow
through it for ~1 s (zero calibration, LED on). A residual offset can be corrected afterwards from the
app ("Calibrer" → reference value 0 A, US-39).

## 4. Option A — everything with Docker (recommended for the demo)

Needs Docker with the compose plugin. From the repository root:

```bash
cp .env.example .env        # then replace EVERY value (secrets, MQTT passwords, PUBLIC_BASE_URL=http://<PC_IP>:3000)
docker compose up -d --build
docker compose ps           # db, mosquitto, ml, backend, frontend: running / healthy
curl http://localhost:3000/api/health      # {"statut":"ok","mqtt":"connecte"}
```

- The web app is at `http://<PC_IP>:8080`, the API at `http://<PC_IP>:3000/api`, and the boards connect to
  `<PC_IP>:1883`.
- On start the backend runs the migrations (001–005) and creates the directeur account
  (`SEED_DIRECTEUR_EMAIL` / `SEED_DIRECTEUR_PASSWORD`, to be changed at first login) and machine M01.
- MQTT accounts come from `.env`: `MQTT_BACKEND_PASSWORD` and `MQTT_MACHINES="M01:pwd M02:pwd"` (one per
  board, the same password as in that board's `credentials.py`). After changing them:
  `docker compose up -d --force-recreate mosquitto-init mosquitto`.
- Stop: `docker compose down` (data kept in volumes); `docker compose down -v` erases everything.
- Published images (after the `Images` workflow on `main`) can replace `--build`:
  `ghcr.io/<owner>/predimaint-backend|frontend|ml`.

Then continue with §6 (board), §7 (mobile app) and §8 (first use).

## 5. Option B — development mode (each part by hand)

Commands are run from the repository root unless stated. First time: do every step. Afterwards: steps
5.1 to 5.5 and power the board.

### 5.1 PostgreSQL

```bash
cd backend && docker compose up -d     # PostgreSQL 16 on :5432 (maintenance_iot / maint)
```

### 5.2 MQTT accounts and broker

```bash
cd backend
npm install
npm run mqtt:users:linux                                   # accounts backend + M01 (Linux/macOS)
bash scripts/creer-utilisateurs-mqtt.sh M02 esp32_M02_pwd  # one account per extra machine
npm run mqtt:linux                                         # keep this terminal open
# Windows: npm run mqtt:users  then  npm run mqtt
```

Development passwords: `backend` / `backend_mqtt_pwd`, `M01` / `esp32_M01_pwd`. A running broker reloads
its accounts with `pkill -HUP mosquitto`. The ACL (`mosquitto/config/acl`) includes the OTA topics.

### 5.3 ML service

```bash
cd ml
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/uvicorn predimaint_ml.service:app --host 127.0.0.1 --port 8000   # keep open
curl http://127.0.0.1:8000/health      # {"statut":"ok","modele":"pdm-azure-hgb-48h-1"}
```

The trained model is in the repository (`ml/models/`). Retraining is optional (see `ml/README.md`).
Without this service the platform works, only the failure risk is missing.

### 5.4 Backend

```bash
cd backend
cp .env.example .env     # two long random JWT secrets, MQTT_URL/MQTT_PASSWORD, CORS_ORIGINS, PUBLIC_BASE_URL, ML_URL
npm run db:migrate       # migrations 001-006 (Release 3: 004, predictions: 005, sensor presence: 006)
npm run db:seed          # directeur account + machine M01 with its 4 sensors and thresholds
npm start                # http://localhost:3000/api/health -> {"statut":"ok","mqtt":"connecte"}
```

The log must show `MQTT connecté`, `Abonné à : usine/machines/+/mesures, usine/machines/+/statut,
usine/machines/+/ota/statut` and `Seuils envoyés aux cartes`.

**Updating an existing installation** (for example the dev PC running the Release 2 backend): stop the
backend, `git pull`, `npm install`, `npm run db:migrate`, `npm start`. The migrations only add columns
and tables.

### 5.5 Web app

```bash
cd frontend && npm install
npm start                          # http://localhost:4200
npx ng serve --host 0.0.0.0        # from another PC: http://<PC_IP>:4200
```

### 5.6 Useful backend commands

| Command | Story | What it does |
|---|---|---|
| `npm run db:backup` / `npm run db:restore -- <file>` | US-44 | `pg_dump` backup with rotation (14 kept) / restore (asks for confirmation) |
| `npm run db:archive [-- <days>]` | US-40 | archive measures older than N days now (also automatic, daily) |
| `npm run rapport -- mois-precedent html` | US-17 | write last month's report to `rapports/` (cron-friendly) |
| `npm run firmware:publier` | US-46 | publish the current firmware (`FIRMWARE_VERSION` of `config.py`) for remote updates |
| `npm run demo -- historique M01` / `pannes M01` / `nettoyer` | US-50 | demo data: normal history for the AI, past failures for the KPIs; cleanup |
| `npm run simulateur` / `node scripts/simulateur-esp32.js M01 anomalie` | — | a simulated board (normal or drifting) |

## 6. ESP32 board

```bash
cd partie_embarque
pipx install esptool mpremote               # once
./esp.sh flash                              # once per board (hold BOOT if it cannot connect)
cp src/credentials_example.py src/credentials.py
# credentials.py: WIFI_SSID, WIFI_PASSWORD, MQTT_HOST = "<PC_IP>", MQTT_PASSWORD, MACHINE_CODE (default M01), MQTT_PORT
./esp.sh deploy                             # copies boot.py, ota.py and the firmware, reboots, opens the serial log
```

The serial log shows `firmware version 1.3.0`, then one line per cycle (`#12 I=1.210 A vib=3.4/s ...
sent 1`). The serial monitor holds the port: close it (`Ctrl-]`) before running `./esp.sh` again.

**Remote updates (US-46)**: once a board runs a firmware with `ota.py`, later versions no longer need the
USB cable. Raise `FIRMWARE_VERSION` in `src/config.py`, then `cd backend && npm run firmware:publier`, then
in the mobile app (responsable) open the machine sheet → "Firmware de la carte" → install. The board
checks every file's SHA-256, reboots, and reports the result. It goes back to the previous version by
itself if the new one does not start.

## 7. Mobile app (Android)

Full guide (in French): [`../mobile/README.md`](../mobile/README.md). Needs Flutter **3.50+** and the
Android SDK on the PC.

```bash
cd mobile
flutter pub get
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
```

Install it in one of these ways:

- **USB**: `adb install -r build/app/outputs/flutter-apk/app-release.apk` (USB debugging on, prompt accepted).
- **No cable**: on the PC run `python3 -m http.server 8099 --directory build/app/outputs/flutter-apk`, open
  `http://<PC_IP>:8099/app-release.apk` in the phone's browser, install, then stop the server.

Then open **PrédiMaint**. On the login screen, the **"Serveur : …"** line shows the address in use; tap it
to change it, then **Tester** → "Connexion réussie" → **Enregistrer**. Typing the IP alone is enough:
`:3000/api` is added. The address is kept on the phone and survives updates. A new install defaults to
`192.168.45.116:3000` (or the `--dart-define=API_BASE_URL=...` given at build time).

| Situation | "Serveur" value |
|---|---|
| phone is the hotspot, PC connected to it (project setup) | the PC's address on the hotspot, e.g. `192.168.45.116` |
| phone and PC on the same Wi-Fi | the PC's address on that Wi-Fi |
| phone on USB, any network | `127.0.0.1` after `adb reverse tcp:3000 tcp:3000` |
| Android emulator | `10.0.2.2` |

If "Tester" fails, open `http://<PC_IP>:3000/api/health` in the phone's browser. If that fails too, the
backend is down, the IP is wrong, or the PC firewall blocks port 3000.

## 8. First use

1. Directeur (web): log in with the seed account and choose a new password. Under "Chefs de production",
   create a responsable de maintenance and note the temporary password shown once. Under
   "Notifications", choose the channels (in-app level, e-mail if SMTP is configured).
2. Responsable (mobile): log in (new password at first login), then "Plus" → Techniciens → create the
   technicians. Machine M01 already exists. Another board needs an MQTT account and its `MACHINE_CODE`.
3. Responsable: adjust the thresholds in the machine sheet (the board's LED follows them), and set the
   hourly downtime cost (web, Indicateurs) so that downtime has a price.
4. Technicien (mobile): "Mes interventions", then start, report, photos and close.

## 9. Check the chain

- `mosquitto_sub -h <PC_IP> -u backend -P <pwd> -t 'usine/machines/#' -v` shows the board's messages every
  5 s.
- Machine sheet: sensors "En ligne", values change live, and the "Mesures" tab draws the curve with its
  thresholds.
- Warm the DHT22 above 45 °C, shake the SW-420 or draw more than 3 A: an alert and a notification appear,
  the machine turns orange/red and the LED lights.
- Failure risk (demo): set `PREDICTION_PAS_S=60` in `.env`, restart the backend, run
  `npm run demo -- historique M01`, let the board run normally (risk FAIBLE), then make it drift: the risk
  rises to ELEVE, usually before the threshold alerts.
- Unplug the board: within ~20 s the machine turns grey. Plug it back: buffered measures arrive.

## 10. Tests

| Part | Command | Count |
|---|---|---|
| backend unit | `cd backend && npm test` | 20 |
| backend integration (real PostgreSQL, wipes the target DB) | `TEST_DATABASE_URL=postgres://maint:maint_password@localhost:5432/maintenance_iot_test npm run test:integration` | 16 |
| firmware logic on the PC | `cd partie_embarque && python -m pytest tests_host` | 21 |
| one sensor on the board | `cd partie_embarque && ./esp.sh run dht22` (or `sw420`, `acs712`) | — |
| ML | `cd ml && .venv/bin/python -m pytest` | 12 |
| mobile | `cd mobile && flutter analyze && flutter test` | 35 |
| web | `cd frontend && npx ng build && npx ng test --watch=false` | 4 |

The same tests run in GitHub Actions on every push (see `DEVSECOPS.md`).

## 11. Production notes

- Put HTTPS in front of the API and the web app (reverse proxy and certificate) and set strong secrets in
  `.env`.
- Use MQTT over TLS (listener 8883 is prepared in `backend/mosquitto/config/mosquitto.conf`) with strong
  board passwords.
- Schedule backups (`npm run db:backup` in cron, or `pg_dump` of the compose database) and copy them off
  the machine.
- Notifications reach phones while the app is open (real-time stream) and by e-mail. Push to a closed
  phone needs Firebase Cloud Messaging (not set up).
