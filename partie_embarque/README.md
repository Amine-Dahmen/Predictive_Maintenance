# PrediMaint - ESP32 firmware (MicroPython)

The ESP32 reads the three sensors and publishes the measurements to the MQTT
broker every 5 s (backlog US-18 *Collecte des mesures*, US-49 *Firmware ESP32
de base*). The backend (`../backend`) stores them, compares them to the
thresholds set in the application and raises the alerts shown in the web app
(`../frontend`). The message format is the team's MQTT contract:
[`backend/docs/CONTRAT_MQTT.md`](../backend/docs/CONTRAT_MQTT.md).

```
DHT22 ──┐
SW-420 ─┼─ ESP32 ──Wi-Fi/MQTT──> mosquitto ──> backend (PostgreSQL, alerts) ──> web app
ACS712 ─┘   └─ LED on while a local threshold is exceeded
```

## Wiring (all three sensors at once)

| Sensor / part | Sensor pin | ESP32 pin   | Notes |
|---------------|------------|-------------|-------|
| DHT22         | VCC        | **3V3**     | |
|               | DATA       | **GPIO21**  | 4.7k-10k pull-up to 3V3 (most modules have one) |
|               | GND        | GND         | |
| SW-420        | VCC        | **3V3**     | not 5V, so DO never goes above 3.3 V |
|               | DO         | **GPIO19**  | sensitivity: blue potentiometer on the module |
|               | GND        | GND         | |
| ACS712        | VCC        | **5V / VIN**| |
|               | OUT        | **GPIO34**  | through the 10k/20k divider below, never directly |
|               | GND        | GND         | |
|               | IP+ / IP-  | -           | in series with the load to measure |
| Alert LED     |            | GPIO2       | the on-board LED of most devkits, nothing to wire |

All grounds are common (GND of the ESP32 and of the three modules).

ACS712 divider (the output idles at 2.5 V and can reach ~4.5 V, too high for
the ESP32):

```
ACS712 OUT ──[10k]──┬──[20k]── GND
                    └── GPIO34
```

Why these pins:
- **GPIO21** DHT22: unchanged from the standalone test.
- **GPIO19** SW-420: GPIO21 is taken by the DHT22. GPIO19 is a plain digital
  pin, not a boot strapping pin.
- **GPIO34** ACS712: an ADC1 pin. ADC2 pins stop working when Wi-Fi is on, and
  GPIO21 has no ADC.
- Avoid GPIO0, 2, 5, 12 and 15 (strapping pins, they change how the board
  boots) and GPIO6-11 (internal flash) if you add more parts.

Set `ACS712_SENSITIVITY` in `src/config.py` for your module (5A = 0.185,
20A = 0.100, 30A = 0.066 V/A) and `CURRENT_MODE` (`"rms"` for AC loads,
`"dc"` for DC loads). At boot the LED lights for ~1 s while the ACS712 zero
offset is measured: **no current may flow then**.

## Setup

Tools: `pipx install esptool mpremote` (or `pip install -r requirements.txt`).
On Arch your user has to be in the `uucp` group for serial access.
`umqtt.simple`, `ntptime`, `dht` and `machine.ADC` are built into the firmware
in `firmware/` (MicroPython v1.29.0), so nothing else has to be installed.

1. Start the broker and the backend (see `../docs/ARCHITECTURE_DEPLOIEMENT.md`).
2. Declare the machine in the web app (responsable de maintenance → Machines →
   Nouvelle machine, "Carte ESP32 PrédiMaint" ticked). The demo machine `M01`
   already exists after `npm run db:seed`.
3. Create the board's MQTT account, username = machine code:
   `bash backend/scripts/creer-utilisateurs-mqtt.sh M01 esp32_M01_pwd`
   (`npm run mqtt:users` on Windows creates `M01` too).
4. `cp src/credentials_example.py src/credentials.py`, then fill in the Wi-Fi,
   the PC's IP (`MQTT_HOST`), `MQTT_PASSWORD` and, for another machine,
   `MACHINE_CODE`. This file is git-ignored.
5. Flash and deploy:

```sh
./esp.sh flash            # once per board: erase + install MicroPython
./esp.sh start            # run the firmware live from src/ (Ctrl-C to stop), good for debugging
./esp.sh deploy           # copy it to the board: runs at every boot, then opens the monitor
./esp.sh monitor          # serial console / REPL (Ctrl-] to quit)
```

If `flash` can't connect, hold the **BOOT** button while it starts.

Serial output, one line per cycle (every 5 s):

```
#12 I=1.210 A vib=3.4/s (17 edges) T=24.3 C H=51.0 % alerts=- sent
LOCAL ALERT RAISED high: temperature=46.1 (limit 45.0)
```

## MQTT messages

| Topic | QoS | When | Payload |
|-------|-----|------|---------|
| `usine/machines/<MACHINE_CODE>/mesures` | 1 | every 5 s | see below |
| `usine/machines/<MACHINE_CODE>/statut` | 1, retained | connect / last will | `online`, then `offline` when the board disappears |
| `usine/machines/<MACHINE_CODE>/config` | received, retained | at connect and when a threshold changes in the app | `{"seuils": {"courant": {"alerte": 3, "critique": 4.5}, ...}}` |

```json
{"courant": 1.21, "vibration": 3.4, "temperature": 24.3, "humidite": 51.0, "ts": 1792745000,
 "seq": 12, "uptime_s": 60, "alertes_locales": []}
```

| Field | Unit | Sensor |
|-------|------|--------|
| `courant` | A (RMS, or mean for `CURRENT_MODE = "dc"`) | ACS712 |
| `vibration` | SW-420 edges per second | SW-420 |
| `temperature` | C | DHT22 |
| `humidite` | % | DHT22 |
| `ts` | UTC Unix time in seconds from NTP, omitted until the sync succeeded | - |

A sensor that fails to read is sent as `null`. `seq`, `uptime_s` and
`alertes_locales` are for debugging; the backend ignores them.

If Wi-Fi or the broker is lost (US-45), the board keeps measuring: the Wi-Fi
reconnection runs in the background (retry delay growing from 5 s to 60 s) and
the messages wait in RAM (`BUFFER_SIZE` = 180, 15 min at 5 s; the oldest are
dropped when full). Once reconnected they are sent oldest first, 20 per cycle,
with their original timestamp. Messages produced before the first NTP sync
have no timestamp, so they are only sent live, never buffered.

## Alert thresholds

The reference alerts are raised by the **backend**, from the thresholds set in
the application for each machine (seuil d'alerte / seuil critique).

The board also has local thresholds that only drive the LED, so a technician
next to the machine sees a problem without the app. They follow the thresholds
set in the application (US-11): the backend sends them on the `config` topic
at each connection and whenever they change, and the board alerts above the
"seuil d'alerte". Until then the defaults of `THRESHOLDS` in `src/config.py`
apply, as `metric: (min, max, hysteresis, confirm)`:

| Metric        | Unit                  | Default LED threshold |
|---------------|-----------------------|-----------------------|
| `courant`     | A                     | > 3.0                 |
| `vibration`   | SW-420 edges / second | > 20                  |
| `temperature` | C                     | > 45                  |
| `humidite`    | %                     | > 80                  |

A local alert is raised after `confirm` consecutive out-of-range cycles and
clears only once the value is back inside the range by `hysteresis`.

## Files

| File | Role |
|------|------|
| `src/main.py` | main loop: read, local thresholds, publish |
| `src/config.py` | pins, intervals, thresholds, machine code |
| `src/credentials.py` | Wi-Fi + MQTT secrets (git-ignored, from `credentials_example.py`) |
| `src/sensors.py` | DHT22, SW-420 and ACS712 drivers |
| `src/alerts.py` | threshold rules with hysteresis / confirmation, updated from the app |
| `src/buffer.py` | messages waiting while offline (US-45) |
| `src/net.py` | Wi-Fi, NTP, MQTT with reconnect and last will |
| `tests/test_*.py` | standalone test per sensor: `./esp.sh run dht22 \| sw420 \| acs712` |
| `tests_host/` | PC unit tests of the alert logic and the buffer: `python -m pytest tests_host` |


## Remote firmware update (US-46)

`boot.py` and `ota.py` are deployed with the firmware (`./esp.sh deploy`). Afterwards a new version can be
installed without the USB cable:

1. raise `FIRMWARE_VERSION` in `src/config.py`;
2. `cd ../backend && npm run firmware:publier` (copies `main, config, net, sensors, alerts, buffer, ota`,
   never `credentials.py` or `boot.py`, with their SHA-256);
3. mobile app (responsable) → machine sheet → "Firmware de la carte" → install.

The board downloads each file to `<name>.new` and checks size and SHA-256 against the order received over
MQTT (only the backend can write it: broker ACL). Nothing is replaced if one file is wrong. It then swaps
the files (old ones kept as `.bak`) and reboots. While the new version is on trial, `boot.py` starts a
120 s watchdog that `main.py` feeds; after 3 boots without confirmation it restores the `.bak` files.
Once connected, the board reports `REUSSI` and deletes the backups. Logic tested on the PC:
`python -m pytest tests_host/test_ota.py`.
