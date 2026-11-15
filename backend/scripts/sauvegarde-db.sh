#!/usr/bin/env bash
# US-44 : sauvegarde de la base PostgreSQL (format custom de pg_dump, compressé).
# Usage : bash scripts/sauvegarde-db.sh [dossier]      (npm run db:backup)
#   - utilise pg_dump s'il est installé, sinon celui du conteneur Docker "db" (docker compose)
#   - garde les BACKUP_KEEP dernières sauvegardes (14 par défaut) ; à planifier avec cron, par ex. :
#     0 2 * * * cd /chemin/backend && bash scripts/sauvegarde-db.sh >> backups/sauvegarde.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."

# Variables DB_* du fichier .env (sans écraser celles déjà définies dans l'environnement)
if [[ -f .env ]]; then
  while IFS='=' read -r k v; do
    [[ "$k" =~ ^DB_[A-Z_]+$ ]] && [[ -z "${!k:-}" ]] && export "$k=$v"
  done < <(grep -E '^DB_[A-Z_]+=' .env)
fi
DB_HOST=${DB_HOST:-localhost}; DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-maintenance_iot}; DB_USER=${DB_USER:-maint}; DB_PASSWORD=${DB_PASSWORD:-maint_password}
DEST=${1:-backups}; KEEP=${BACKUP_KEEP:-14}
mkdir -p "$DEST"
FILE="$DEST/${DB_NAME}_$(date +%Y%m%d_%H%M%S).dump"

if command -v pg_dump >/dev/null 2>&1; then
  PGPASSWORD="$DB_PASSWORD" pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Fc -f "$FILE"
else
  docker compose exec -T db pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc > "$FILE"
fi

# Une sauvegarde vide ou illisible est supprimée et signalée
if [[ ! -s "$FILE" ]] || ! head -c 5 "$FILE" | grep -q PGDMP; then
  rm -f "$FILE"; echo "ERREUR : sauvegarde invalide" >&2; exit 1
fi
echo "Sauvegarde créée : $FILE ($(du -h "$FILE" | cut -f1))"

# Rotation
ls -1t "$DEST"/"${DB_NAME}"_*.dump 2>/dev/null | tail -n +"$((KEEP + 1))" | xargs -r rm -f
