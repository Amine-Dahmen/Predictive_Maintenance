# Drivers for the three PrediMaint sensors.
# Same logic as the standalone tests in tests/, wrapped so that main.py can
# read all of them in one cycle. A failed read returns None instead of raising.

import time
import dht
from machine import ADC, Pin


class DHT22Sensor:
    """Temperature (C) and relative humidity (%)."""

    def __init__(self, pin):
        self.sensor = dht.DHT22(Pin(pin, Pin.IN, Pin.PULL_UP))
        self.errors = 0

    def read(self):
        # one retry: a single checksum error now and then is normal
        for attempt in range(2):
            try:
                self.sensor.measure()
                return self.sensor.temperature(), self.sensor.humidity()
            except OSError:
                self.errors += 1
                if attempt == 0:
                    time.sleep_ms(2100)  # the DHT22 needs 2 s between reads
        return None, None


class VibrationSensor:
    """SW-420: counts every edge on DO with an interrupt.

    read() returns the edge rate (edges per second) since the previous call,
    which is used as the vibration level.
    """

    def __init__(self, pin):
        self.pin = Pin(pin, Pin.IN)
        self.edges = 0
        self.last = time.ticks_ms()
        self.pin.irq(trigger=Pin.IRQ_RISING | Pin.IRQ_FALLING, handler=self._on_edge)

    def _on_edge(self, _pin):
        self.edges += 1

    def read(self):
        now = time.ticks_ms()
        n = self.edges
        self.edges = 0
        elapsed = time.ticks_diff(now, self.last) / 1000
        self.last = now
        rate = n / elapsed if elapsed > 0 else 0.0
        return n, rate

    def stop(self):
        self.pin.irq(handler=None)


class CurrentSensor:
    """ACS712 hall-effect current sensor on an ADC1 pin.

    read() samples during window_ms and returns (dc, rms) in amps:
      dc   mean current, for DC loads
      rms  RMS of the AC part, for mains / AC motor loads
    """

    def __init__(self, pin, sensitivity, divider, window_ms):
        self.adc = ADC(Pin(pin), atten=ADC.ATTN_11DB)  # ~0-3.1 V input range
        self.sensitivity = sensitivity
        self.divider = divider
        self.window_ms = window_ms
        self.zero = 2.5

    def volts(self):
        # read_uv() applies the factory calibration, more accurate than read()
        return self.adc.read_uv() / 1000000 / self.divider

    def calibrate(self, samples):
        """Measure the zero-current output. No current must flow meanwhile."""
        acc = 0.0
        for _ in range(samples):
            acc += self.volts()
        self.zero = acc / samples
        return self.zero

    def read(self):
        # accumulate deviations from the zero offset: floats are single
        # precision on the ESP32, summing squares of ~2.5 V would lose the signal
        n = 0
        s = 0.0
        s2 = 0.0
        zero = self.zero
        start = time.ticks_ms()
        while time.ticks_diff(time.ticks_ms(), start) < self.window_ms:
            d = self.volts() - zero
            s += d
            s2 += d * d
            n += 1
        mean = s / n
        var = s2 / n - mean * mean
        rms_v = var ** 0.5 if var > 0 else 0.0
        return mean / self.sensitivity, rms_v / self.sensitivity
