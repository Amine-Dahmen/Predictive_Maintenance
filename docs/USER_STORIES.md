# How each user story is implemented

All 50 stories of the backlog (`PrediMaint_Product_Backlog_Roadmap.xlsx`), grouped by release. For each:
where it lives, how it works, and how it is checked. Paths are relative to the repository root. API routes
are under `/api` (see `backend/docs/API.md`).

Abbreviations: **BE** backend (`backend/src`), **FW** firmware (`partie_embarque/src`), **MOB** mobile app
(`mobile/lib`), **WEB** web app (`frontend/src/app`), **ML** prediction service (`ml/`).
Tests: `BE-unit` = `backend/tests/unit.test.js`, `BE-int` = `backend/tests/integration/*.test.js`,
`FW` = `partie_embarque/tests_host`, `MOB` = `mobile/test`, `WEB` = `*.spec.ts`, `ML` = `ml/tests`.

Release 2 is the **mobile** release: its stories are implemented in the mobile app (by the front-end team)
on top of the backend. The web versions written earlier were removed on 2026-11-12 (commit "Web: remove the
Release 2 work now provided by the mobile app").

---

## Release 1 — sensors → MQTT → backend → alert

| US | Title | Implementation | Checked by |
|---|---|---|---|
| US-47 | Git repository and Trello board | One repository for every part. Work on feature branches merged into `main` with merge commits, descriptive commit messages. Since Release 3, CI on every push (`.github/workflows/ci.yml`) | git history, CI |
| US-48 | MQTT broker | Mosquitto 2 with the team configuration (`backend/mosquitto/config/`): no anonymous access, password file, ACL. Linux scripts `npm run mqtt:users:linux`, `npm run mqtt:linux`. Docker version: `deploy/mosquitto/` + root `docker-compose.yml` (accounts generated from `.env`) | compose smoke test |
| US-49 | Basic ESP32 firmware | MicroPython: `main.py` loop every 5 s, `sensors.py` drivers, `net.py` Wi-Fi + MQTT (`umqtt.simple`), NTP time, LED on GPIO2. `esp.sh` flashes, deploys and runs the tests on the board | `./esp.sh run <sensor>` |
| US-18 | Sensor data collection | `sensors.py`: DHT22 (GPIO21) temperature and humidity; SW-420 (GPIO19) vibration as interrupt-counted pulses per second; ACS712 (GPIO34 through a 10k/20k divider) RMS or DC current with zero calibration at boot. One JSON message per cycle on `usine/machines/<code>/mesures` | `partie_embarque/tests/` on the board |
| US-19 | Measure storage | BE `mqtt/mesure.handler.js`: zod validation, plausibility ranges (`utils/mesures.js`), one row per measure in `mesures`, board timestamp accepted if consistent. Migration 002 added TEMPERATURE and HUMIDITE | BE-unit (payload, timestamps) |
| US-20 | Threshold breach detection | Per-machine alert/critical thresholds (`seuils`). The handler creates one open alert per sensor (unique partial index), escalates ALERTE → CRITIQUE, recomputes the machine state (`services/etatMachine.service.js`), publishes SSE events | BE-unit (levels) |
| US-23 | Machine and sensor declaration | `POST /machines` with `kitPredimaint: true` creates the 4 board sensors and default thresholds in one transaction; `POST /machines/:id/capteurs`. WEB: declaration form (kept on web) | BE-int (setup of every test) |
| US-41 | MQTT security | Username = machine code, per-machine ACL (`pattern write usine/machines/%u/...`): a board cannot publish for another machine or read another board's thresholds or OTA orders. Last will `offline` | manual (ACL test of Release 1), compose smoke test |
| US-42 | API security | JWT access (15 min) + rotating hashed refresh tokens (reuse revokes every session), bcrypt, password policy, login rate limit, RBAC on every route, zod validation, helmet, CORS allow-list | BE-unit (JWT, refresh, policy) |

## Release 2 — mobile app, monitoring, interventions

| US | Title | Implementation | Checked by |
|---|---|---|---|
| US-45 | Wi-Fi loss on the ESP32 | FW `net.py`: non-blocking reconnection, 5 s socket timeout. `buffer.py`: RAM ring buffer of 180 messages (15 min) replayed with original timestamps, 20 per cycle | FW `test_buffer.py` |
| US-21 | Offline sensor detection | Board last will → sensors offline → machine SANS_DONNEES at once; periodic check of sensors from which nothing was **received** for 60 s (server clock, migration 006 `derniere_reception_at`, so a board/PC clock difference cannot flip sensors offline); one SSE `capteur.etat` per machine when it goes offline and when it comes back (`services/surveillanceCapteurs.service.js`, `mqtt/mesure.handler.js`). Board timestamps more than 20 min away from the server clock are replaced by server time with a log warning. MOB: one notification per board and real state change (`BoardStatusTracker`) | BE-int `presence.test.js`, MOB `roles_test.dart` |
| US-11 | Alert threshold configuration | `PUT /machines/:id/seuils/:type` (responsable), published retained on `.../config` so the board's LED follows (`mqtt/seuils.publisher.js`). MOB: "Configurer les seuils" on the machine sheet | MOB `machines_page_test.dart`, BE-unit |
| US-43 | Alert delay | Migration 003: each alert keeps the time of its triggering measure; API returns `delaiDetectionS`. MOB: delay per alert and average (≈ 0.1–0.2 s measured) | MOB alerts page |
| US-01, US-02 | Vibration / temperature and current alerts | Alerts on every measure type; SSE `alerte.creee` sent to technicians too. MOB: snackbar notification, real open-alert badge on the Alerts tab (the hardcoded "3" was replaced during verification) | MOB `release2_fixes_test.dart` |
| US-27 | Push notifications | MOB `services/realtime_notifications_service.dart`: SSE client with reconnection and token refresh; in-app notifications for alerts, assignments, boards offline/online, high failure risk. (Closed-app push would need FCM: not set up) | manual |
| US-03 | Alert acknowledgement | `PATCH /alertes/:id/prise-en-compte` (responsable or technician). MOB: "Prendre en compte" (hidden for the directeur, whom the API refuses) | MOB `release2_fixes_test.dart` |
| US-30 | Alert closure | `PATCH /alertes/:id/cloture` with a mandatory comment; machine state recomputed. MOB: "Clôturer" with comment | BE-int |
| US-12 | Alert history | `GET /alertes` with period, status, level, machine filters. MOB: filter block on the Alerts page | MOB `alerts_page_test.dart` |
| US-10 | Machine state dashboard | MOB dashboard: machines per state and colour-coded machine cards, refreshed periodically and on events | MOB `dashboard_widgets_test.dart` |
| US-09 | Machine sheet | MOB `views/machines/machines_page.dart`: tabs sensors & thresholds / measures / history | MOB `machines_page_test.dart` |
| US-04 | Measure history | `GET /machines/:id/mesures`. MOB: period (24 h / 7 d / 30 d) and sensor filters, list of measures and, added during verification, a **curve** with alert/critical lines and gaps while the board was offline (`views/shared/measure_chart.dart`) | MOB `release2_fixes_test.dart` |
| US-05 | Machine failure history | `GET /machines/:id/historique` (alerts + interventions). MOB: history tab with a "failures only" filter | MOB |
| US-13 | Intervention planning | `POST /interventions` (preventive with a date, curative, predictive from an alert with priority and due date). MOB: creation dialog; on an alert, "Planifier une intervention" (responsable) creates the predictive intervention, optionally assigned at once | MOB `machines_interventions_refresh_test.dart` |
| US-14 | Intervention assignment | `PATCH /interventions/:id/affecter`: active technician, due date, conflict warnings for the same day; SSE `intervention.affectee` to the technician | BE-int (US-29 test) |
| US-06, US-07 | Maintenance / repair intervention | Technician: `demarrer` → `PUT compte-rendu` (diagnostic, actions, parts, draft) → `cloturer` with result. "Remise en service" closes the machine's alerts and ends the failure. MOB: the detail sheet carries the whole flow (start button, status read from the API, guidance per step), also reachable from the machine sheet ("Mes interventions sur cette machine") | BE-int, MOB `roles_test.dart` |
| US-26 | My assigned interventions | `GET /interventions` filtered server-side to the technician's own. MOB: technician home and Interventions tab | MOB |
| US-08 | Mobile authentication | MOB login → `POST /auth/login`, forced password change, automatic token refresh (`services/api_client.dart`), logout revokes the refresh token. The server address is set on the login screen and saved on the phone (`config/api_config.dart`, `views/auth/server_settings.dart`), so a new PC IP needs no rebuild | MOB `api_client_test.dart`, `config/api_config_test.dart` |
| US-24 | Accounts and roles | `/responsables` (directeur) and `/techniciens` (responsable): create with a one-time temporary password, edit, activate/deactivate. MOB: technicians and responsables pages | MOB `widget_test.dart` |

## Release 3 — reliability, steering, bonus

| US | Title | Implementation | Checked by |
|---|---|---|---|
| US-50 | Demo mock-up | `backend/scripts/demo.js` (`npm run demo`): `historique` writes 191 steps of normal measures so the AI has a reference at once, `pannes` adds past repairs for the KPIs, `nettoyer` removes both (local state file). Simulated board in normal or drift mode. Scenario in `ARCHITECTURE_DEPLOIEMENT.md` §9 | end-to-end run of 2026-11-12 |
| US-39 | Sensor calibration | Migration 004: `calibration_gain`, `calibration_offset` per sensor. `PATCH /capteurs/:id/calibration` (responsable, technician) takes gain/offset, or `valeurReference`: the offset is computed so that the current value becomes the reference (e.g. 0 A with the motor stopped). Applied in the MQTT handler to new measures (`valeur = gain × raw + offset`). MOB: "Calibrer" dialog | BE-unit (formula), BE-int, MOB `release3_test.dart` |
| US-46 | Remote firmware update | BE `modules/firmware`: `npm run firmware:publier` copies the firmware (never `credentials.py`) with a SHA-256 manifest. `POST /machines/:id/firmware` publishes the order on `.../ota` (ACL: only that board reads it) with a download URL carrying a random, hashed token valid 30 min. The board reports on `.../ota/statut`. FW `ota.py`: downloads to `.new`, verifies size and SHA-256 **before** replacing anything, keeps `.bak`, reboots; `boot.py` counts unconfirmed boots, arms a watchdog and restores the old files after 3 failures; `REUSSI` once connected. MOB: firmware page with history | FW `test_ota.py` (tampered/truncated files, forbidden names, rollback), BE-int |
| US-40 | Archiving old measures | `services/archivage.service.js`: daily, measures older than `MESURES_RETENTION_JOURS` (90) are summarised per sensor and hour (count, mean, min, max, weighted merge) in `mesures_horaires`, then deleted. `GET /machines/:id/mesures-horaires`; `npm run db:archive` | BE-int (weighted merge) |
| US-44 | Database backup | `scripts/sauvegarde-db.sh` (`npm run db:backup`): `pg_dump -Fc` (local or in the Docker container), validity check, rotation (14). `scripts/restaurer-db.sh` with confirmation. Cron line in the script header | manual run |
| US-22 | Failure probability (bonus) | **ML**: model trained on the Azure Predictive Maintenance dataset with unit-free features relative to each machine's own last week, target "failure within 48 h", calibrated gradient boosting (details and honest results in `ml/README.md`). FastAPI service. **BE** `services/prediction.service.js`: every 5 min, 192 step means per machine → `/predict/batch` → table `predictions` (migration 005) → SSE `prediction.maj`, and `prediction.risque` when a machine enters the high level. **MOB**: risk card with history on the machine sheet + notification. **WEB**: risk table on the indicators page | ML (12), BE-unit, BE-int (`prediction.test.js`), MOB, WEB |
| US-31 | False alarm marking | Migration 004: `alertes.fausse_alerte`. `PATCH /alertes/:id/fausse-alerte` (responsable) with a reason closes and marks the alert. Excluded from per-machine counts and reports, shown as FAUSSE_ALERTE in the history, filter `?fausseAlerte=true`. MOB: "Fausse alerte" with a reason | BE-int |
| US-32 | Machine comparison | `GET /machines/comparaison?ids=1,2&type=…`: per-type statistics (count, mean, min, max, standard deviation), a series aggregated to ~60 points (`date_bin`), alerts, availability, failures, MTBF/MTTR. MOB: comparison page (machine chips, measure, period, cards with curves) | BE-int, MOB |
| US-29 | Manual failure declaration | `POST /machines/:id/pannes` (**responsable**, as in the backlog): creates the repair (CURATIVE intervention) with the failure start, optionally assigned to a technician at once (US-14). The machine goes to PANNE until the technician closes the repair with "remise en service"; the failure counts in MTBF/MTTR and downtime. MOB: "Déclarer une panne" on the machine sheet (responsable), "Interventions en cours" card on the sheet showing who must act | BE-int, MOB `roles_test.dart` |
| US-25 | Photo attached to an intervention | Migration 004: `intervention_photos`. `POST /interventions/:id/photos` (multipart, multer in memory): JPEG/PNG **detected from the bytes**, 5 MB, 10 per intervention, server-generated name. Served with the JWT only to users who can see the intervention; the technician deletes only their own. MOB: camera or gallery (`image_picker`, resized to 1600 px), thumbnails, zoomable viewer | BE-unit (type detection), BE-int (fake file, size, access) |
| US-28 | Offline mode and sync | MOB `services/api_client.dart` + `offline_store.dart`: successful reads of interventions, machines and alerts are cached on the phone (`shared_preferences`). Without network they are served from the cache and the app shows an offline banner. A report draft saved offline is queued (one per intervention, the latest wins) and replayed in order when the server answers again; a draft refused by the server (intervention closed meanwhile) is dropped and reported. Closing an intervention still needs the network | MOB `offline_test.dart` (cache, queue, rejection, restart) |
| US-15 | Availability indicators | Existing KPI engine (`modules/indicateurs`): availability, MTBF, MTTR, OEE per machine and for the plant. WEB: indicators page with a period selector | BE-unit, WEB |
| US-16 | Failure duration and frequency | `GET /indicateurs/pannes?grain=week|month`: count, downtime, mean duration and cost per period. `frequencePannes30j` and `dureeMoyennePanneH` per machine. WEB: bar list "Évolution des pannes" | BE-int, WEB spec |
| US-33 | Summary dashboard | `GET /indicateurs/dashboard` + `topArrets` (machines with the most downtime). WEB: KPI tiles, fleet/failures/alerts/top-downtime cards | BE-int, WEB spec |
| US-34 | Downtime cost | Migration 004: `machines.cout_horaire_arret`. `PATCH /machines/:id/cout` (directeur, responsable); `coutArret = downtime (h) × hourly cost` per machine, summed for the plant, per period. WEB: editable hourly cost per machine, cost tile | BE-int, WEB spec |
| US-17 | Periodic maintenance report | `GET /rapports/maintenance?format=json|csv|html` for a period or `periode=mois-precedent|semaine-precedente`: KPIs, per machine, closed interventions, alert statistics (false alarms, acknowledgement delay). CSV with BOM and formula-injection protection; HTML escaped, strict CSP, printable to PDF. `npm run rapport` for cron. WEB: "Rapport (imprimable)", "Export CSV", "Mois précédent" | BE-unit, BE-int (escaping) |
| US-35 | Password reset | `POST /responsables/:id/reinitialiser-mot-de-passe` (directeur) and `/techniciens/:id/…` (responsable): new temporary password shown once, forced change, every session revoked, open real-time stream closed. WEB (responsables) and MOB (technicians) | BE-int |
| US-36 | Account deactivation | Existing `PATCH …/statut`; Release 3 adds `session.revoquee` so the open SSE stream is closed at once. MOB returns to the login screen | BE-int (stream closed, 401 after) |
| US-37 | Sensor replacement | `POST /capteurs/:id/remplacer` (responsable): new sensor (id given or `<old>-R2`, `-R3`…), old one retired (`retire_at`, `remplace_par`) with its history kept, its open alerts closed; measures go to the newest active sensor of that type. MOB: "Remplacer", retired sensors shown "Retiré" | BE-int, MOB |
| US-38 | Notification channels | Migration 004: `canaux_notification` (APP, EMAIL: active, minimum level, extra recipients). `GET/PUT /notifications/canaux` (directeur). APP: every alert event carries `notifier` and the apps only notify when it is true. EMAIL: nodemailer to active responsables and the extra recipients when `SMTP_HOST` is set (logged otherwise), also on escalation. WEB: "Notifications" page | BE-unit, BE-int |

## Extension requested on 2026-11-13 (not in the backlog)

In the backlog, assignment is the responsable's (US-14); the technician carries out what he is given
(US-06, US-07, US-26). At the team's request, a technician can also take work himself, without waiting:

- **"À prendre"** in his Interventions tab: unassigned interventions (`GET /interventions?aPrendre=true`),
  with "Prendre en charge" (`PATCH /interventions/:id/prendre-en-charge`). Only one technician can take a
  given intervention (conditional update, 409 otherwise), and the responsables are notified.
- **"Prendre en charge la panne"** on a machine in PANNE with nobody on it: the technician declares the
  failure and the repair is assigned to him at once (`POST /machines/:id/pannes`), so it is never orphaned.
- Checked by BE-int (`release3.test.js`, extension test) and MOB `roles_test.dart`.

## Cross-cutting work done with Release 3

- **Release 2 verification** (mobile): analysis and the 12 existing tests passed. Five defects were
  fixed: hardcoded alert badge, missing measure curve, acknowledge button shown to the directeur,
  "machine" instead of the code in offline notifications, and four unused screens (one with demo data).
- **Build**: the Android project was moved to Gradle 9.5 / AGP 9.3.1 (Flutter 3.50 minimum). Unused
  `swagger-jsdoc` was removed and nodemailer kept ≥ 10.2, so `npm audit` is clean for production
  dependencies.
- **DevSecOps** (`docs/DEVSECOPS.md`): CI, gitleaks, CodeQL, npm audit / pip-audit, Trivy, Dependabot,
  images with SBOM and provenance, full-stack `docker-compose.yml`.
