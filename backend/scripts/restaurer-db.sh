#!/usr/bin/env bash
# US-44 : restauration d'une sauvegarde créée par sauvegarde-db.sh. REMPLACE le contenu de la base.
# Usage : bash scripts/restaurer-db.sh backups/maintenance_iot_20261112_020000.dump [--oui]
# Arrêtez le backend avant de restaurer.
set -euo pipefail
cd "$(dirname "$0")/.."
FILE=${1:?Usage : restaurer-db.sh <fichier.dump> [--oui]}
[[ -f "$FILE" ]] || { echo "Fichier introuvable : $FILE" >&2; exit 1; }
if [[ -f .env ]]; then
  while IFS='=' read -r k v; do
    [[ "$k" =~ ^DB_[A-Z_]+$ ]] && [[ -z "${!k:-}" ]] && export "$k=$v"
  done < <(grep -E '^DB_[A-Z_]+=' .env)
fi
DB_HOST=${DB_HOST:-localhost}; DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-maintenance_iot}; DB_USER=${DB_USER:-maint}; DB_PASSWORD=${DB_PASSWORD:-maint_password}

if [[ "${2:-}" != "--oui" ]]; then
  read -r -p "La base $DB_NAME va être remplacée par $FILE. Continuer ? (oui/non) " r
  [[ "$r" == "oui" ]] || { echo "Annulé."; exit 1; }
fi
if command -v pg_restore >/dev/null 2>&1; then
  PGPASSWORD="$DB_PASSWORD" pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" --clean --if-exists --no-owner "$FILE"
else
  docker compose exec -T db pg_restore -U "$DB_USER" -d "$DB_NAME" --clean --if-exists --no-owner < "$FILE"
fi
echo "Base $DB_NAME restaurée depuis $FILE"
