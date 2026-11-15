# DHT22 (AM2302) temperature / humidity test.
#
# Wiring:
#   DHT22 VCC  -> 3V3
#   DHT22 DATA -> GPIO21  (needs a 4.7k-10k pull-up to 3V3; most breakout boards include it)
#   DHT22 GND  -> GND
#
# Uses the `dht` driver that ships built into the MicroPython ESP32 firmware.

import time
import dht
from machine import Pin

DATA_PIN = 21
INTERVAL_S = 2  # the DHT22 cannot be read faster than once every 2 s

sensor = dht.DHT22(Pin(DATA_PIN, Pin.IN, Pin.PULL_UP))

print("DHT22 test on GPIO%d - Ctrl-C to stop" % DATA_PIN)
time.sleep(2)  # sensor needs ~1-2 s after power-up before first read

ok = 0
errors = 0
t_min = h_min = 1e9
t_max = h_max = -1e9

try:
    while True:
        try:
            sensor.measure()
            t = sensor.temperature()
            h = sensor.humidity()
            ok += 1
            t_min, t_max = min(t_min, t), max(t_max, t)
            h_min, h_max = min(h_min, h), max(h_max, h)
            print("T = %5.1f C   H = %5.1f %%   (T %.1f..%.1f, H %.1f..%.1f)  ok=%d err=%d"
                  % (t, h, t_min, t_max, h_min, h_max, ok, errors))
        except OSError as e:
            # ETIMEDOUT -> no answer (wiring / power / pull-up); EIO -> checksum error
            errors += 1
            print("read failed: %r  ok=%d err=%d" % (e, ok, errors))
        time.sleep(INTERVAL_S)
except KeyboardInterrupt:
    print("\nstopped. successful reads: %d, failed reads: %d" % (ok, errors))
