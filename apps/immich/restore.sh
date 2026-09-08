#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/immich-YYYYMMDDTHHMMSSZ.tar" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$script_dir"

if [[ -f "$script_dir/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$script_dir/.env"
  set +a
fi

upload_location="${IMMICH_UPLOAD_LOCATION:-./library}"
db_volume="${IMMICH_DB_VOLUME:-immich-database}"
db_username="${IMMICH_DB_USERNAME:-immich}"
db_database_name="${IMMICH_DB_DATABASE_NAME:-immich}"

mkdir -p "$upload_location"
upload_path="$(cd "$upload_location" && pwd)"

# A safety copy of the current state before an irreversible replacement.
bash "$script_dir/backup.sh"

staging="$(mktemp -d)"
cleanup() {
  rm -rf "$staging"
}
trap cleanup EXIT
tar -C "$staging" -xf "$archive" database.sql.gz library.tar.gz

# A restore needs a completely clean database: upstream forbids loading a dump
# over a schema the server has already used.
docker compose down --remove-orphans --timeout 30
docker volume rm --force "$db_volume" >/dev/null

docker run --rm \
  -v "${upload_path}:/target" \
  -v "${staging}:/staging:ro" \
  alpine:3.22 \
  sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /staging/library.tar.gz'

docker compose create
docker compose up --detach --wait --wait-timeout 300 database

gunzip --stdout "$staging/database.sql.gz" \
  | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
  | docker compose exec -T database \
    psql --dbname="$db_database_name" --username="$db_username" \
    --single-transaction --set ON_ERROR_STOP=on >/dev/null

docker compose up --detach --wait --wait-timeout 600

echo "Backup restored from: $archive"
