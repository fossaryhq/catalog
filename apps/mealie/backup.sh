#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="$app_dir/.env.example"
if [[ -f "$app_dir/.env" ]]; then
  env_file="$app_dir/.env"
  set -a
  # shellcheck disable=SC1091
  . "$env_file"
  set +a
fi
project="${COMPOSE_PROJECT_NAME:-mealie}"
volume="${MEALIE_DATA_VOLUME:-mealie-data}"
backup_dir="${MEALIE_BACKUP_DIR:-$app_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
compose=(docker compose --project-name "$project" --env-file "$env_file" --file "$app_dir/compose.yaml")
mkdir -p "$backup_dir"

# Quiesce SQLite and uploads together before archiving the data volume.
"${compose[@]}" stop mealie
restart_container() { "${compose[@]}" start mealie >/dev/null; }
trap restart_container EXIT

docker run --rm -v "${volume}:/source:ro" -v "$backup_dir:/backup" alpine:3.22 \
  tar -C /source -czf "/backup/mealie-${timestamp}.tar.gz" .
echo "Backup created: $backup_dir/mealie-${timestamp}.tar.gz"
