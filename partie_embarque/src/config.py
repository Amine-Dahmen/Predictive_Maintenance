# PrediMaint ESP32 firmware configuration.
#
# Wi-Fi and MQTT credentials do NOT go here: copy credentials_example.py to
# credentials.py (git-ignored) and fill it in. Anything defined in
# credentials.py overrides the defaults below.

# Version announced to the backend (US-46). Increase it before
# `npm run firmware:publier` (backend) so the boards can be updated over the air.
FIRMWARE_VERSION = "1.3.0"

# ---- identity --------------------------------------------------------------
# Code of the machine the board is mounted on, as declared in the application.
# It is also the MQTT username, so the broker ACL only lets this board publish
# under usine/machines/<MACHINE_CODE>/ (backend/docs/CONTRAT_MQTT.md).
MACHINE_CODE = "M01"

# ---- network ---------------------------------------------------------------
WIFI_SSID = ""
WIFI_PASSWORD = ""
WIFI_TIMEOUT_S = 20

MQTT_HOST = "192.168.1.10"  # IP of the PC / server running mosquitto
MQTT_PORT = 1883
MQTT_PASSWORD = ""          # this machine's MQTT account (backend/scripts/creer-utilisateurs-mqtt.*)
MQTT_KEEPALIVE_S = 15       # value of the MQTT contract: the broker publishes "offline" ~20 s after a crash
TOPIC_PREFIX = "usine/machines/"

NTP_HOST = "pool.ntp.org"   # time is synced at boot; UTC timestamps

# ---- pins ------------------------------------------------------------------
PIN_DHT22 = 21     # DHT22 DATA (digital, 4.7k-10k pull-up to 3V3)
PIN_SW420 = 19     # SW-420 DO (digital, interrupt-counted)
PIN_ACS712 = 34    # ACS712 OUT through the 10k/20k divider (ADC1, input only)
PIN_LED = 2        # on-board LED of most ESP32 devkits, lit while an alert is active

# ---- sampling --------------------------------------------------------------
SAMPLE_INTERVAL_S = 5        # one measurement message per cycle (DHT22 needs >= 2 s)

# which ACS712 reading is sent as "courant": "rms" for AC loads (motors on the
# mains), "dc" for DC loads (absolute value of the mean current)
CURRENT_MODE = "rms"
ACS712_SENSITIVITY = 0.185   # V/A: 5A -> 0.185, 20A -> 0.100, 30A -> 0.066
ACS712_DIVIDER = 20.0 / (10.0 + 20.0)  # V_adc = V_sensor * DIVIDER (1.0 if wired directly)
ACS712_WINDOW_MS = 100       # sampling window per reading (5 periods of 50 Hz)
ACS712_CALIB_SAMPLES = 2000  # zero-offset calibration at boot: NO current must flow

# ---- local alert thresholds ------------------------------------------------
# The backend is the reference for alerts (thresholds set in the application).
# These local rules only drive the LED, so a technician next to the machine
# sees a problem even without the app. Same values as the backend defaults
# ("seuil d'alerte" of backend/src/utils/mesures.js).
#
# metric: (min, max, hysteresis, confirm)
#   min / max   alert when the value goes below min or above max (None = no limit)
#   hysteresis  the alert clears only once the value is back inside by this margin
#   confirm     number of consecutive out-of-range cycles before raising the alert
# Metrics are the MQTT fields: courant (A), vibration (SW-420 pulses per second),
#                              temperature (C), humidite (%)
THRESHOLDS = {
    "courant": (None, 3.0, 0.2, 2),
    "vibration": (None, 20.0, 5.0, 2),
    "temperature": (None, 45.0, 1.0, 2),
    "humidite": (None, 80.0, 3.0, 2),
}

# ---- Wi-Fi loss (US-45) ----------------------------------------------------
# Messages that could not be sent are kept in RAM and sent once the link is
# back, oldest first, with their original timestamp. 180 x 5 s = 15 min of
# measurements (~30 KB); when full the oldest messages are dropped.
BUFFER_SIZE = 180
FLUSH_PER_CYCLE = 20         # buffered messages sent per cycle after a reconnection

# ---- robustness ------------------------------------------------------------
# Hardware watchdog: resets the board if the main loop hangs. 0 = disabled.
# Keep it at 0 while developing: once started it can't be stopped, so the
# board reboots a few seconds after you Ctrl-C the program.
WDT_TIMEOUT_MS = 0

try:
    from credentials import *  # noqa: F401,F403
except ImportError:
    pass
