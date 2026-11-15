#!/usr/bin/env bash
# Crée / met à jour les comptes MQTT sous Linux ou macOS (équivalent de creer-utilisateurs-mqtt.ps1).
#
#   bash scripts/creer-utilisateurs-mqtt.sh                    comptes backend + M01 (mots de passe du .env.example)
#   bash scripts/creer-utilisateurs-mqtt.sh M02 motdepasse     ajoute / modifie le compte d'une machine
#
# Le nom d'utilisateur d'un ESP32 est le code de sa machine (règle de l'ACL).
# Un broker déjà démarré relit le fichier après : pkill -HUP mosquitto
set -euo pipefail
cd "$(dirname "$0")/.."

passwd=mosquitto/config/passwd
if command -v mosquitto_passwd >/dev/null; then
    mp() { mosquitto_passwd -b "$passwd" "$1" "$2"; }
else
    mp() { docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/mosquitto/config:/c" eclipse-mosquitto:2 \
               mosquitto_passwd -b /c/passwd "$1" "$2"; }
fi

touch "$passwd"
chmod 600 "$passwd"
if [[ $# -ge 2 ]]; then
    mp "$1" "$2"
    echo "compte MQTT '$1' enregistré"
else
    mp backend "${BACKEND_PWD:-backend_mqtt_pwd}"
    mp M01 "${M01_PWD:-esp32_M01_pwd}"
    echo "comptes MQTT 'backend' et 'M01' enregistrés dans $passwd"
fi
