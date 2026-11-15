#!/bin/sh
# Crée le fichier de mots de passe du broker à partir des variables d'environnement (service mosquitto-init).
# MQTT_MACHINES="M01:motdepasse M02:autre" : un compte par carte ESP32 (nom = code machine)
set -eu
f=/mosquitto/passwd/passwd
: > "$f"
mosquitto_passwd -b "$f" backend "$MQTT_BACKEND_PASSWORD"
for m in $MQTT_MACHINES; do
  mosquitto_passwd -b "$f" "${m%%:*}" "${m#*:}"
done
chmod 0700 "$f"
chown mosquitto:mosquitto "$f" 2>/dev/null || true
echo "comptes MQTT : backend $(for m in $MQTT_MACHINES; do printf '%s ' "${m%%:*}"; done)"
