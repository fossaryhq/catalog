#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/freshrss-YYYYMMDDTHHMMSSZ.tar" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$script_dir"
if [[ ! -f .env ]]; then
  echo "Missing $script_dir/.env" >&2
  exit 2
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a

data_volume="${FRESHRSS_DATA_VOLUME:-freshrss-data}"
extensions_volume="${FRESHRSS_EXTENSIONS_VOLUME:-freshrss-extensions}"
db_volume="${FRESHRSS_DB_VOLUME:-freshrss-database}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -C "$staging" -xf "$archive" database.sql.gz data.tar.gz extensions.tar.gz configuration.env compose.yaml

# Preserve the state that will be irreversibly replaced.
bash "$script_dir/backup.sh"
docker compose down --remove-orphans --timeout 60
docker volume rm --force "$data_volume" "$extensions_volume" "$db_volume" >/dev/null
docker volume create "$data_volume" >/dev/null
docker volume create "$extensions_volume" >/dev/null
docker run --rm -v "${data_volume}:/target" -v "${staging}:/restore:ro" alpine:3.22 tar -C /target -xzf /restore/data.tar.gz
docker run --rm -v "${extensions_volume}:/target" -v "${staging}:/restore:ro" alpine:3.22 tar -C /target -xzf /restore/extensions.tar.gz

docker compose up --detach --wait --wait-timeout 300 database
gunzip -c "$staging/database.sql.gz" | docker compose exec -T database psql --set ON_ERROR_STOP=1 --dbname="${FRESHRSS_DB_NAME:-freshrss}" --username="${FRESHRSS_DB_USER:-freshrss}"
docker compose up --detach --wait --wait-timeout 300 freshrss

echo "Backup restored from: $archive"
echo "The archived configuration.env was not activated. Compare it with .env and keep FreshRSS at the archived version until verification."
