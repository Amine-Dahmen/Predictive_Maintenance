# SW-420 vibration sensor module test (digital output).
#
# Wiring:
#   SW-420 VCC -> 3V3   (power it from 3V3, NOT 5V, so DO never exceeds 3.3 V)
#   SW-420 DO  -> GPIO19   (GPIO21 is taken by the DHT22 in the full firmware)
#   SW-420 GND -> GND
#
# The module's comparator output toggles while the spring switch is shaken.
# Sensitivity is set with the blue potentiometer on the module.
# Every edge on DO is counted with an interrupt, so even very short
# pulses are caught; a summary is printed each REPORT_MS.

import time
from machine import Pin

DATA_PIN = 19
REPORT_MS = 500

pin = Pin(DATA_PIN, Pin.IN)
edges = 0
total_edges = 0
events = 0


def on_edge(p):
    global edges
    edges += 1


pin.irq(trigger=Pin.IRQ_RISING | Pin.IRQ_FALLING, handler=on_edge)

print("SW-420 test on GPIO%d - Ctrl-C to stop" % DATA_PIN)
print("idle level: %d  (tap the sensor; adjust the pot if nothing is detected)" % pin.value())

try:
    while True:
        time.sleep_ms(REPORT_MS)
        n = edges
        edges = 0
        total_edges += n
        if n:
            events += 1
            print("VIBRATION  edges=%-4d level=%d  events=%d total_edges=%d"
                  % (n, pin.value(), events, total_edges))
        else:
            print("quiet      level=%d" % pin.value())
except KeyboardInterrupt:
    pin.irq(handler=None)
    print("\nstopped. vibration events: %d, total edges: %d" % (events, total_edges))
