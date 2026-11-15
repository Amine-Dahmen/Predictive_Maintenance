# Work summary — Releases 1 to 3, failure prediction, DevSecOps

Context for the team and for the next work session. Written 2026-11-05, updated 2026-11-12
(see the section "Session of 2026-11-12" at the end).
How to run everything: [`ARCHITECTURE_DEPLOIEMENT.md`](ARCHITECTURE_DEPLOIEMENT.md).
Backlog: `docs/version_commune.xlsx` (same content as `PrediMaint_Product_Backlog_Roadmap.xlsx`).

## Where things are

- Repository: `maintenance-pr-dictive-iot` (GitHub `faroukbensalem/maintenance-pr-dictive-iot`).
- Branches, all merged into `main` with merge commits (nothing pushed yet):
  - `feature/partie-embarque` — firmware imported + Release 1 adaptation of backend and frontend
  - `feature/release-2` — Release 2 (firmware, backend, frontend)
- `partie_embarque/` is a copy of the separate `../partie_embarque` repository (its own git history,
  left untouched). From now on the firmware lives in this repository.
- `../partie_software/` (SQLite backend written before the team backend existed) is **obsolete**: the
  team's Node.js backend replaced it. It was not copied into this repository.

## Release 1 — chain sensors → MQTT → backend → alert

| US | What was done |
|---|---|
| US-49, US-18 | MicroPython firmware: DHT22 (GPIO21), SW-420 (GPIO19, interrupt-counted pulses/s), ACS712 (GPIO34 through a 10k/20k divider, RMS or DC current), 1 message every 5 s, local LED thresholds, NTP timestamps, reconnection |
| US-48, US-41 | Team Mosquitto config kept (no anonymous access, ACL per machine). Added Linux scripts: `npm run mqtt:users:linux`, `npm run mqtt:linux` (configurable port) |
| US-19 | Backend stores the 4 measure types. New types TEMPERATURE and HUMIDITE (migration 002); one shared list of types, units, ranges and default thresholds in `backend/src/utils/mesures.js` |
| US-20 | Team alert engine kept (alert / critical thresholds per machine). MQTT payload extended: `temperature`, `humidite`, `null` for a failed sensor read, debug fields ignored |
| US-23 | `POST /machines` with `kitPredimaint: true` creates the 4 board sensors and default thresholds in one transaction; UI form for the responsable to declare machines and sensors |
| US-42 | Team JWT security kept; frontend now refreshes expired tokens, revokes the refresh token at logout, forces the password change at first login, enforces roles on routes |
| US-47 | Work done in git branches with descriptive commits |

The firmware was adapted to the team's MQTT contract rather than the reverse: topic
`usine/machines/<code>/mesures`, MQTT username = machine code, plain `online`/`offline` retained status
with last will. The contract document (`backend/docs/CONTRAT_MQTT.md`) was updated for the 4 fields.

Frontend Release 1: the shell became role-aware (directeur / responsable / technicien), a
`RealtimeService` consumes the backend SSE stream, the machine sheet shows the 4 sensors live with their
thresholds, the alert list and dashboard show the right fields (they used `Machine #id` and a wrong KPI
path before), and the API address follows the page host so phones on the LAN work.

## Release 2 — app, monitoring, interventions

| US | Where | What was done |
|---|---|---|
| US-45 Wi-Fi loss | firmware | non-blocking Wi-Fi reconnection, 5 s socket timeout (a dead link cannot freeze the loop), RAM ring buffer of 180 messages (15 min) replayed with original timestamps, 20 per cycle |
| US-21 sensor offline | backend + app | board last will puts the machine in SANS_DONNEES immediately; offline/online notifications in the app |
| US-11 thresholds | backend + app + firmware | thresholds edited in the machine sheet; backend publishes them retained on `usine/machines/<code>/config`; the board's LED follows them; ACL: each board reads only its own |
| US-01, US-02 | backend + app | alerts for vibration, temperature, current (and humidity) reach technicians too (SSE roles) |
| US-03 | backend + app | acknowledgement by responsable **or technician** (route opened to TECHNICIEN) |
| US-30 | app | closure with a mandatory comment (the old button sent no comment and always failed) |
| US-12 | app | alert history with period, status, level and machine filters |
| US-43 | backend + app | each alert stores the time of its triggering measure (migration 003); API returns `delaiDetectionS`; shown per alert and as an average (measured ≈ 0.1–0.2 s) |
| US-04 | app | measure curves per sensor (1 h / 24 h / 7 days) with alert and critical lines, hover and keyboard readout, table view, live append, gaps when the board was offline |
| US-05, US-09 | app | machine sheet with tabs Capteurs / Mesures / Historique; history of alerts and interventions with a "failures only" filter |
| US-10 | app | dashboard with machines per state and live colour-coded machine cards |
| US-13, US-14 | app | plan preventive / curative interventions, predictive ones from an alert, assign to a technician (conflict warnings from the API shown), cancel |
| US-06, US-07, US-26 | app | technician "Mes interventions": start, report (diagnostic, actions, parts, draft), close with result; closing "remise en service" closes the machine's alerts |
| US-24 | app | technician accounts page for the responsable; the one-time temporary password is now displayed for new technicians and responsables |
| US-27 | app | notifications: in-app toasts for new alerts, boards offline/online and assigned interventions; system notifications when the tab is in the background (needs HTTPS or localhost) |
| US-08 | app | phone layout (stacked cards, profile/logout reachable, profile page fixed on narrow screens), web app manifest to install it on the home screen; API auth (JWT + refresh rotation) already suits a mobile client |

## How it was verified

- Backend unit tests: 12/12 (`npm test`), firmware logic tests: 9/9 (`pytest tests_host`), frontend build
  and tests pass.
- End to end on the development PC with PostgreSQL (Docker), the project Mosquitto with ACL, the backend
  and the Angular app, and the **real firmware code** run on the PC with stubbed hardware modules
  (`machine`, `dht`, `network`; `umqtt` mapped onto paho-mqtt). Not tested on the physical board in this
  session: wiring, sensor readings and timing on the real ESP32 still need a check.
- Checked end to end: 4 measure types stored; temperature alert created and escalated to CRITIQUE after
  a threshold change; Wi-Fi outage of 6 s → 9 messages buffered and all delivered (76 rows = 19 cycles × 4
  sensors); threshold change in the app received by the board; ACL blocks M01 from M02's topics;
  anonymous and wrong-password connections refused.
- Browser (headless Chromium): first login with forced password change, responsable creating a machine
  with the board kit, technician account, live sensor values, curve, history, live alert toast,
  predictive intervention from an alert, assignment, technician on a phone-sized screen receiving the
  assignment notification, starting, reporting and closing; alerts closed automatically.

## Known limitations and points to watch

- `esp.sh` is bash: Windows users need Git Bash/WSL, or the `mpremote` commands it wraps.
- The Windows script `npm run mqtt:users` recreates the password file (`-c`): it erases accounts added
  later for other machines. The Linux script adds accounts without erasing.
- Creating a machine in the app does not create its MQTT account: run
  `scripts/creer-utilisateurs-mqtt.sh <code> <password>` (or `mosquitto_passwd`) and reload the broker.
- Measurements taken before the first NTP sync have no timestamp, so they are never buffered.
- The backend raises an alert on the first measurement above a threshold (no confirmation count) and
  keeps it open until a person closes it; the board's LED uses hysteresis and clears on its own.
- Notifications only reach open sessions; true push to a closed phone needs a mobile app or Web Push
  (US-38, Release 3). The directeur's KPI pages were not changed.
- On the development PC a system Mosquitto listens on 1883 with anonymous access; the project broker
  was tested on port 1884.
- `npm install` with a newer npm rewrites `package-lock.json` (only `"peer": true` lines); those changes
  were left out of the commits.

## Next steps

1. Push `main` (and the two branches if wanted) to GitHub, after the team reviews the changes.
2. Wire the 3 sensors, flash the board and run Step 7 of the deployment guide on the real hardware;
   tune `ACS712_SENSITIVITY`, the SW-420 potentiometer and the thresholds.
3. Release 3 from the backlog: US-50 demo mock-up, US-39 sensor calibration (ACS712 zero, offsets),
   US-40 / US-44 measure archiving and database backups, US-31 false alerts, US-29 manual failure
   declaration, US-32 machine comparison, US-15/16/33/34 production KPIs and costs, US-35/36/37 account
   and sensor administration, US-25 photo on interventions, US-28 offline mode, US-38 notification
   channels, US-46 OTA firmware update, US-22 failure probability (bonus).

---

## Session of 2026-11-12 — Release 2 verification, Release 3, AI, DevSecOps

Per-story details: [`USER_STORIES.md`](USER_STORIES.md). How to run everything:
[`ARCHITECTURE_DEPLOIEMENT.md`](ARCHITECTURE_DEPLOIEMENT.md). AI: [`../ml/README.md`](../ml/README.md).
CI/security: [`DEVSECOPS.md`](DEVSECOPS.md).

Commits on `main` (each merged from its branch):

| Commit | Content |
|---|---|
| `1882717` | Release 3 backend (migration 004), web pages for the directeur, firmware OTA |
| `ddf8af3` | Release 2 verification: mobile fixes (real alert badge, measure curve, directeur acknowledgement, offline notification text, dead screens) |
| `e90a546` | Release 3 mobile (offline mode, photos, calibration, failure declaration, sensor replacement, false alarms, comparison, firmware, password reset) |
| `914749b` | US-22: dataset, model, ML service, backend integration (migration 005), risk in both apps |
| `d8ca65c` | DevOps/DevSecOps: CI, security scans, images, full-stack compose |
| `1df5ab3` | Web: Release 2 removed from the web app (it is in the mobile app) |
| `a0776c8` | Mobile build with Flutter 3.50 (Gradle 9.5, AGP 9.3.1) |

### Verification state

- Tests: backend unit 20/20, backend integration 13/13 (real PostgreSQL), firmware host 21/21, ML 12/12,
  mobile 26/26, web 4/4. `flutter analyze`: no warnings (only the Flutter 3.47+ `material.dart`
  deprecation notices). `npm audit --omit=dev` clean. gitleaks: history clean.
- End to end on an isolated stack (broker :1884, backend :3100, ML :8100, database
  `maintenance_iot_e2e`): demo history plus simulated board gave **FAIBLE 1.4%**; a drift gave **ELEVE 82%**,
  raised 9 s before the first threshold alert (compressed demo time).
- Docker: the three images build, and the compose stack starts healthy (smoke test on shifted ports, then
  removed).
- Phone (Samsung Galaxy A12): debug APK installed, `adb reverse tcp:3000 tcp:3100`.
- **Not checked**: the physical board with the new firmware (its serial port was in use by a running
  `./esp.sh deploy` monitor, and the PC was not on the board's network). Remote update on the real board
  and the e-mail channel with a real SMTP server are also unchecked.

### Points to watch

- `partie_embarque/src/credentials_example.py` was edited with real Wi-Fi values in the working copy: it
  must not be committed (the CI secret scan blocks it). Restore it with
  `git checkout partie_embarque/src/credentials_example.py`; real values belong in `credentials.py`.
- The dev backend still running on :3000 was not restarted. Migrate it with `npm run db:migrate`, then
  restart it to get Release 3.
- The mobile project now needs Flutter 3.50+.
- AI: trained on a synthetic public dataset. Its probabilities are a risk score to confirm by inspection,
  and it should be retrained on the plant's own data once available (procedure in `ml/README.md`).
