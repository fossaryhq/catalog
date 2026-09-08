#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/miniflux-YYYYMMDDTHHMMSSZ.tar" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$script_dir"
env_file="${FOSSARY_ENV_FILE:-$script_dir/.env}"
if [[ ! -e "$env_file" ]]; then
  echo "Missing $env_file" >&2
  exit 2
fi
set -a
# shellcheck disable=SC1091
. "$env_file"
set +a
compose=(docker compose --env-file "$env_file")

db_volume="${MINIFLUX_DB_VOLUME:-miniflux-database}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -C "$staging" -xf "$archive" database.sql.gz configuration.env compose.yaml

# Preserve the state that will be irreversibly replaced.
bash "$script_dir/backup.sh"
"${compose[@]}" down --remove-orphans --timeout 60
docker volume rm --force "$db_volume" >/dev/null

"${compose[@]}" up --detach --wait --wait-timeout 300 database
gunzip -c "$staging/database.sql.gz" | "${compose[@]}" exec -T database psql --set ON_ERROR_STOP=1 --dbname="${MINIFLUX_DB_NAME:-miniflux}" --username="${MINIFLUX_DB_USER:-miniflux}"
"${compose[@]}" up --detach --wait --wait-timeout 300 miniflux

echo "Backup restored from: $archive"
echo "The archived configuration.env was not activated. Compare it with .env and keep Miniflux at the archived version until the restore is verified."
