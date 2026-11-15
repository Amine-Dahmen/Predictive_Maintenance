# PrediMaint ESP32 firmware: reads DHT22 + SW-420 + ACS712, lights the LED on
# local threshold alerts and publishes the measurements over MQTT (US-18, US-49).
#
# Every SAMPLE_INTERVAL_S:
#   1. read the current, vibration rate, temperature and humidity
#   2. check the local thresholds -> LED on while any alert is active. They
#      start from config.py and follow the thresholds set in the application,
#      received on usine/machines/<MACHINE_CODE>/config (US-11)
#   3. publish one message on usine/machines/<MACHINE_CODE>/mesures:
#        {"courant": 1.21, "vibration": 3.4, "temperature": 24.3, "humidite": 51.0, "ts": 1792745000, ...}
#      The backend stores it and raises the alerts shown in the application.
#      If Wi-Fi or the broker is down, the message is kept and sent later (US-45).
#
#   4. remote firmware update (US-46): an order received on .../ota is
#      downloaded, verified (SHA-256) and installed, then the board reboots
#
# Files on the board: boot.py main.py config.py credentials.py sensors.py alerts.py buffer.py net.py ota.py
# (./esp.sh deploy copies them). Serial output shows each cycle.

import gc
import json
import time
from machine import Pin, WDT, reset

import config as cfg
from alerts import AlertMonitor
import ota
from buffer import RingBuffer
from net import Link
from sensors import CurrentSensor, DHT22Sensor, VibrationSensor


def r(x, nd=2):
    return None if x is None else round(x, nd)


def main():
    led = Pin(cfg.PIN_LED, Pin.OUT, value=0)
    dht22 = DHT22Sensor(cfg.PIN_DHT22)
    vibration = VibrationSensor(cfg.PIN_SW420)
    current = CurrentSensor(cfg.PIN_ACS712, cfg.ACS712_SENSITIVITY,
                            cfg.ACS712_DIVIDER, cfg.ACS712_WINDOW_MS)

    print("PrediMaint firmware - machine %s" % cfg.MACHINE_CODE)
    print("pins: DHT22=GPIO%d SW-420=GPIO%d ACS712=GPIO%d LED=GPIO%d"
          % (cfg.PIN_DHT22, cfg.PIN_SW420, cfg.PIN_ACS712, cfg.PIN_LED))

    # ACS712 zero offset: no current must flow during the first second
    led.value(1)
    time.sleep(1)
    zero = current.calibrate(cfg.ACS712_CALIB_SAMPLES)
    led.value(0)
    print("ACS712 zero offset = %.3f V" % zero)
    if not 2.0 < zero < 3.0:
        print("WARNING: ACS712 offset far from 2.5 V - check supply, wiring and ACS712_DIVIDER")

    monitor = AlertMonitor(cfg.THRESHOLDS)

    def apply_config(msg):
        changed = monitor.set_limits(msg.get("seuils", {}))
        if changed:
            print("thresholds from the application: %s"
                  % ", ".join("%s>%s" % (m, monitor.rules[m].hi) for m in changed))

    ota_order = []  # filled by the MQTT callback, handled in the main loop

    def report_ota(statut, message, deploiement=None, version=None):
        link.publish("ota/statut", {"statut": statut, "message": message,
                                    "deploiement": deploiement if deploiement is not None else (ota_order[0].get("deploiement") if ota_order else None),
                                    "version": version or (ota_order[0].get("version") if ota_order else None)})

    def on_connect():
        ota.confirm(report_ota, cfg.FIRMWARE_VERSION)

    link = Link(cfg, on_config=apply_config, on_ota=lambda o: ota_order.append(o), on_connect=on_connect)
    print("firmware version %s" % cfg.FIRMWARE_VERSION)
    link.start()
    pending = RingBuffer(cfg.BUFFER_SIZE)

    wdt = None
    if cfg.WDT_TIMEOUT_MS:
        wdt = WDT(timeout=cfg.WDT_TIMEOUT_MS)
    elif ota.pending():
        wdt = WDT(timeout=120000)  # started by boot.py for a version on trial: keep feeding it
    boot = time.ticks_ms()
    seq = 0

    while True:
        start = time.ticks_ms()
        seq += 1

        temperature, humidity = dht22.read()
        edges, vib_rate = vibration.read()
        i_dc, i_rms = current.read()
        courant = i_rms if cfg.CURRENT_MODE == "rms" else abs(i_dc)

        values = {
            "courant": r(courant, 3),
            "vibration": r(vib_rate, 1),
            "temperature": r(temperature, 1),
            "humidite": r(humidity, 1),
        }
        for ev in monitor.check(values):
            print("LOCAL ALERT %s %s: %s=%s (limit %s)"
                  % (ev["state"].upper(), ev["kind"], ev["metric"], ev["value"], ev["limit"]))
        active = monitor.active()
        led.value(1 if active else 0)

        message = dict(values)
        ts = link.timestamp()
        if ts is not None:  # only once NTP has synced, else the backend uses its own clock
            message["ts"] = ts
        message["seq"] = seq
        message["uptime_s"] = time.ticks_diff(start, boot) // 1000
        message["alertes_locales"] = active

        # Keep the message until it is sent. Without a timestamp a late message
        # would be dated at reception, so it is only kept while the link is up.
        if ts is not None or link.connected():
            pending.push(json.dumps(message))
        link.poll()
        sent = 0
        while len(pending) and sent < cfg.FLUSH_PER_CYCLE:
            if not link.publish("mesures", pending.peek()):
                break
            pending.pop()
            sent += 1

        if sent:
            status = "sent %d" % sent
            if len(pending):
                status += ", %d waiting" % len(pending)
        else:
            status = "OFFLINE, %d waiting (%d dropped)" % (len(pending), pending.dropped)
        print("#%d I=%.3f A vib=%.1f/s (%d edges) T=%s C H=%s %% alerts=%s %s"
              % (seq, courant, vib_rate, edges, values["temperature"], values["humidite"],
                 ",".join(active) or "-", status))

        if ota_order:
            order = ota_order[0]
            print("ota: update to %s requested" % order.get("version"))
            if ota.install(order, ota.http_fetch, report_ota):
                time.sleep(1)  # let the last status message leave
                reset()
            del ota_order[:]

        if wdt:
            wdt.feed()
        gc.collect()
        wait = cfg.SAMPLE_INTERVAL_S * 1000 - time.ticks_diff(time.ticks_ms(), start)
        if wait > 0:
            time.sleep_ms(wait)


main()
