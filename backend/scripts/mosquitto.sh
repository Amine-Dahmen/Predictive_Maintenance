#!/usr/bin/env bash
# Démarre Mosquitto sous Linux / macOS avec la configuration du projet (équivalent de "npm run mqtt").
#
#   bash scripts/mosquitto.sh                 port 1883
#   MQTT_PORT=1884 bash scripts/mosquitto.sh  autre port (si un mosquitto système occupe déjà 1883)
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -s mosquitto/config/passwd ]] || { echo "Aucun compte MQTT : lancez d'abord npm run mqtt:users:linux" >&2; exit 1; }
port="${MQTT_PORT:-1883}"
sed "s/^listener 1883 /listener $port /" mosquitto/config/mosquitto.conf > mosquitto/config/.runtime.conf
exec mosquitto -c mosquitto/config/.runtime.conf
