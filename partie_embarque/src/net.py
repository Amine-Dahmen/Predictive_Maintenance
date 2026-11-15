# Wi-Fi + MQTT link for the ESP32 (umqtt.simple is built into the firmware).
#
# Topics, from the team's MQTT contract (backend/docs/CONTRAT_MQTT.md),
# base = TOPIC_PREFIX + MACHINE_CODE, e.g. usine/machines/M01:
#   <base>/mesures  one JSON message per sampling cycle          (QoS 1, published)
#   <base>/statut   "online" at connect, "offline" as last will   (QoS 1, retained, published)
#   <base>/config   thresholds set in the application            (retained, received)
#   <base>/ota      remote firmware update order (US-46)          (received)
#   <base>/ota/statut  update progress / running version          (published)
#
# A lost connection is not fatal (US-45): ensure() never blocks for long, so
# the board keeps measuring while Wi-Fi reconnects in the background, and
# publish() returns False so main.py keeps the message for later.

import json
import time
import network
import ntptime
from umqtt.simple import MQTTClient

# MicroPython ports use either 1970 or 2000 as time epoch
EPOCH_OFFSET = 0 if time.gmtime(0)[0] == 1970 else 946684800

RETRY_MIN_MS = 5000
RETRY_MAX_MS = 60000
SOCKET_TIMEOUT_S = 5  # a dead connection fails a publish after 5 s instead of blocking forever


class Link:
    def __init__(self, cfg, on_config=None, on_ota=None, on_connect=None):
        self.cfg = cfg
        self.base = cfg.TOPIC_PREFIX + cfg.MACHINE_CODE + "/"
        self.on_config = on_config   # called with the decoded <base>/config message
        self.on_ota = on_ota         # called with the decoded <base>/ota message
        self.on_connect = on_connect # called after each MQTT connection
        self.wlan = network.WLAN(network.STA_IF)
        self.client = None
        self.time_synced = False
        self.wifi_deadline = None    # set while a Wi-Fi connection attempt is running
        self.retry_ms = RETRY_MIN_MS
        self.next_try = time.ticks_ms()
        self.sent = 0
        self.failed = 0

    # ---- connection ----------------------------------------------------

    def _wifi_ready(self):
        """Non-blocking: starts a connection attempt and reports when it is done."""
        if self.wlan.isconnected():
            if self.wifi_deadline is not None:
                print("wifi: connected, ip %s" % self.wlan.ifconfig()[0])
            self.wifi_deadline = None
            return True
        now = time.ticks_ms()
        if self.wifi_deadline is None:
            print("wifi: connecting to %r" % self.cfg.WIFI_SSID)
            self.wlan.active(True)
            self.wlan.connect(self.cfg.WIFI_SSID, self.cfg.WIFI_PASSWORD)
            self.wifi_deadline = time.ticks_add(now, self.cfg.WIFI_TIMEOUT_S * 1000)
            return False
        if time.ticks_diff(self.wifi_deadline, now) <= 0:
            self.wifi_deadline = None
            self.wlan.disconnect()
            raise OSError("wifi timeout")
        return False

    def _sync_time(self):
        if self.time_synced:
            return
        try:
            ntptime.host = self.cfg.NTP_HOST
            ntptime.settime()  # sets the RTC to UTC; it keeps running during later outages
            self.time_synced = True
            print("ntp: time synced")
        except Exception as e:
            print("ntp: sync failed (%r), timestamps will be added by the backend" % e)

    def _on_message(self, topic, msg):
        t = topic.decode()
        handler = None
        if t.endswith("/config"):
            handler = self.on_config
        elif t.endswith("/ota"):
            handler = self.on_ota
        if handler:
            try:
                handler(json.loads(msg))
            except ValueError:
                print("mqtt: unreadable message on %s ignored" % t)

    def _connect_mqtt(self):
        cfg = self.cfg
        client = MQTTClient(
            "esp32-" + cfg.MACHINE_CODE, cfg.MQTT_HOST, port=cfg.MQTT_PORT,
            user=cfg.MACHINE_CODE, password=cfg.MQTT_PASSWORD or None,
            keepalive=cfg.MQTT_KEEPALIVE_S,
        )
        client.set_last_will(self.base + "statut", "offline", retain=True, qos=1)
        client.set_callback(self._on_message)
        client.connect()
        client.sock.settimeout(SOCKET_TIMEOUT_S)
        self.client = client
        client.publish(self.base + "statut", "online", True, 1)
        client.subscribe(self.base + "config", 1)  # retained: the thresholds arrive right away
        client.subscribe(self.base + "ota", 1)
        print("mqtt: connected to %s:%d as %s" % (cfg.MQTT_HOST, cfg.MQTT_PORT, cfg.MACHINE_CODE))
        if self.on_connect:
            try:
                self.on_connect()
            except Exception as e:
                print("mqtt: on_connect failed (%r)" % e)

    def start(self):
        """At boot only: wait (up to WIFI_TIMEOUT_S) for the first connection, so
        that NTP is synced and the first measurements carry a timestamp."""
        deadline = time.ticks_add(time.ticks_ms(), self.cfg.WIFI_TIMEOUT_S * 1000)
        while not self.ensure() and time.ticks_diff(deadline, time.ticks_ms()) > 0:
            time.sleep_ms(200)
        return self.connected()

    def connected(self):
        return self.client is not None and self.wlan.isconnected()

    def ensure(self):
        """Connect if needed, without blocking the measurements. True when MQTT is usable."""
        if self.client is not None:
            if self.wlan.isconnected():
                return True
            print("wifi: connection lost")
            self._drop()
        if time.ticks_diff(self.next_try, time.ticks_ms()) > 0:
            return False
        try:
            if not self._wifi_ready():
                return False         # still connecting: checked again next cycle
            self._sync_time()
            self._connect_mqtt()
            self.retry_ms = RETRY_MIN_MS
            return True
        except Exception as e:
            print("link: connection failed (%r), retry in %d s" % (e, self.retry_ms // 1000))
            self._drop()
            self.next_try = time.ticks_add(time.ticks_ms(), self.retry_ms)
            self.retry_ms = min(self.retry_ms * 2, RETRY_MAX_MS)
            return False

    def _drop(self):
        if self.client is not None:
            try:
                self.client.sock.close()
            except Exception:
                pass
        self.client = None

    # ---- messages ------------------------------------------------------

    def timestamp(self):
        """UTC Unix timestamp in seconds, or None until NTP has synced."""
        return int(time.time()) + EPOCH_OFFSET if self.time_synced else None

    def poll(self):
        """Handle incoming messages (thresholds). Call once per cycle."""
        if self.client is None:
            return
        try:
            self.client.check_msg()
            self.client.sock.settimeout(SOCKET_TIMEOUT_S)  # check_msg leaves the socket blocking
        except Exception as e:
            print("mqtt: connection lost (%r)" % e)
            self._drop()

    def publish(self, sub, payload, retain=False, qos=1):
        """payload: dict, or an already encoded JSON string."""
        if not self.ensure():
            return False
        try:
            msg = payload if isinstance(payload, str) else json.dumps(payload)
            self.client.publish(self.base + sub, msg, retain, qos)
            self.sent += 1
            return True
        except Exception as e:
            print("mqtt: publish failed (%r), reconnecting later" % e)
            self._drop()
            self.failed += 1
            return False
