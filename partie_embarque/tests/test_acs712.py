# ACS712 current sensor test (analog output).
#
# !! GPIO21 has NO ADC on the ESP32, so the ACS712 cannot be read on GPIO21. !!
# Use an ADC1 pin instead: GPIO32-39 (34 is used here). ADC2 pins don't work
# while Wi-Fi is on, so stick to ADC1.
#
# Wiring:
#   ACS712 VCC -> 5V (VIN on the devkit)
#   ACS712 GND -> GND
#   ACS712 OUT -> voltage divider -> GPIO34
#                 OUT --[10k]--+--[20k]-- GND
#                              |
#                            GPIO34
#   The ACS712 output idles at VCC/2 (2.5 V) and can swing to ~4.5 V, which
#   would damage the ESP32 pin, hence the divider (ratio 20k/(10k+20k) = 2/3).
#   If you wire OUT directly (not recommended), set DIVIDER = 1.0.
#
# Keep NO current flowing through the sensor during the first seconds:
# the zero-current offset is measured at startup.

import time
from machine import ADC, Pin

ADC_PIN = 34
DIVIDER = 20.0 / (10.0 + 20.0)  # V_adc = V_sensor * DIVIDER

# Sensitivity in V/A, depends on the variant printed on the chip:
#   ACS712ELCTR-05B -> 0.185   -20A -> 0.100   -30A -> 0.066
SENSITIVITY = 0.185

SAMPLES = 500          # samples per reading (~ several 50 Hz cycles)
REPORT_MS = 1000

adc = ADC(Pin(ADC_PIN), atten=ADC.ATTN_11DB)  # full ~0-3.1 V input range


def sensor_volts():
    # read_uv() uses the factory ADC calibration -> much more accurate than read()
    return adc.read_uv() / 1000000 / DIVIDER


def sample_window(n):
    vals = [0.0] * n
    for i in range(n):
        vals[i] = sensor_volts()
    return vals


print("ACS712 test on GPIO%d - Ctrl-C to stop" % ADC_PIN)
print("calibrating zero offset, make sure no current flows...")
time.sleep(1)
zero = sum(sample_window(2000)) / 2000
print("zero offset = %.3f V (expected ~2.5 V for a 5 V supply)" % zero)
if not 2.0 < zero < 3.0:
    print("WARNING: offset far from 2.5 V - check supply, wiring and DIVIDER")

try:
    while True:
        vals = sample_window(SAMPLES)
        mean = sum(vals) / SAMPLES
        dc = (mean - zero) / SENSITIVITY
        # AC RMS around the mean (for mains / AC loads)
        acc = 0.0
        for v in vals:
            d = v - mean
            acc += d * d
        rms = (acc / SAMPLES) ** 0.5 / SENSITIVITY
        print("Vout = %.3f V   I_dc = %+6.3f A   I_ac_rms = %6.3f A"
              % (mean, dc, rms))
        time.sleep_ms(REPORT_MS)
except KeyboardInterrupt:
    print("\nstopped.")
