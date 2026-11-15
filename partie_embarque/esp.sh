#!/usr/bin/env bash
# Helper to flash MicroPython, deploy the PrediMaint firmware and run the
# sensor tests on an ESP32.
#
#   ./esp.sh ports                 list serial ports
#   ./esp.sh flash                 erase + flash MicroPython firmware (once per board)
#   ./esp.sh deploy                copy the firmware (src/) to the board, reboot + monitor
#   ./esp.sh start                 run the firmware live from src/ without copying it
#   ./esp.sh run     <test>        run a test live from the PC (not saved on the board)
#   ./esp.sh install <test>        save a test as main.py (runs at every boot) + monitor
#   ./esp.sh uninstall             remove main.py from the board
#   ./esp.sh monitor               open the board's serial console / REPL
#
#   <test> = dht22 | sw420 | acs712
#   Set PORT=/dev/ttyUSB1 to pick a port (default: first ttyUSB*/ttyACM* found).
set -euo pipefail

cd "$(dirname "$0")"

FIRMWARE="${FIRMWARE:-firmware/ESP32_GENERIC-20260824-v1.29.0.bin}"
BAUD="${BAUD:-460800}"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

find_port() {
    if [[ -n "${PORT:-}" ]]; then echo "$PORT"; return; fi
    local p
    for p in /dev/ttyUSB* /dev/ttyACM*; do
        [[ -e "$p" ]] && { echo "$p"; return; }
    done
    echo "error: no ESP32 serial port found (is the board plugged in? try ./esp.sh ports)" >&2
    exit 1
}

check_credentials() {
    [[ -f src/credentials.py ]] || {
        echo "error: src/credentials.py missing - copy src/credentials_example.py and fill it in" >&2
        exit 1
    }
}

test_file() {
    local f="tests/test_${1:-}.py"
    [[ -n "${1:-}" && -f "$f" ]] || { echo "error: unknown test '${1:-}' (dht22 | sw420 | acs712)" >&2; exit 1; }
    echo "$f"
}

cmd="${1:-}"; shift || true
case "$cmd" in
    ports)
        mpremote connect list
        ;;
    flash)
        port="$(find_port)"
        [[ -f "$FIRMWARE" ]] || { echo "error: firmware not found: $FIRMWARE" >&2; exit 1; }
        echo ">> erasing flash on $port (hold BOOT if it fails to connect)"
        esptool --chip esp32 --port "$port" --baud "$BAUD" erase-flash
        echo ">> writing $FIRMWARE"
        esptool --chip esp32 --port "$port" --baud "$BAUD" write-flash -z 0x1000 "$FIRMWARE"
        echo ">> done. Check with: ./esp.sh monitor"
        ;;
    deploy)
        check_credentials; port="$(find_port)"
        echo ">> copying firmware to $port"
        mpremote connect "$port" cp src/boot.py src/config.py src/credentials.py src/sensors.py \
            src/alerts.py src/buffer.py src/net.py src/ota.py src/main.py : + reset
        sleep 2
        echo ">> serial monitor (Ctrl-] to quit)"
        mpremote connect "$port" repl
        ;;
    start)
        check_credentials; port="$(find_port)"
        echo ">> running src/ live on $port (Ctrl-C to stop)"
        mpremote connect "$port" mount src exec "import main"
        ;;
    run)
        f="$(test_file "${1:-}")"; port="$(find_port)"
        echo ">> running $f on $port (Ctrl-C to stop)"
        mpremote connect "$port" run "$f"
        ;;
    install)
        f="$(test_file "${1:-}")"; port="$(find_port)"
        echo ">> installing $f as main.py on $port"
        mpremote connect "$port" cp "$f" :main.py + reset
        sleep 2
        echo ">> serial monitor (Ctrl-] to quit)"
        mpremote connect "$port" repl
        ;;
    uninstall)
        port="$(find_port)"
        mpremote connect "$port" rm :main.py && echo ">> main.py removed"
        ;;
    monitor)
        port="$(find_port)"
        mpremote connect "$port" repl
        ;;
    *)
        usage
        ;;
esac
