#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/nextcloud-YYYYMMDDTHHMMSSZ.tar" >&2
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

html_volume="${NEXTCLOUD_HTML_VOLUME:-nextcloud-html}"
db_volume="${NEXTCLOUD_DB_VOLUME:-nextcloud-database}"
db_user="${NEXTCLOUD_DB_USER:-nextcloud}"
db_name="${NEXTCLOUD_DB_NAME:-nextcloud}"

# A safety copy of the current state before an irreversible replacement.
bash "$script_dir/backup.sh"

staging="$(mktemp -d)"
cleanup() {
  rm -rf "$staging"
}
trap cleanup EXIT
tar -C "$staging" -xf "$archive" roles.sql.gz database.sql.gz html.tar.gz

# The dump only loads into a clean database, and the code and config.php are replaced whole.
docker compose down --remove-orphans --timeout 60
docker volume rm --force "$db_volume" >/dev/null
docker run --rm \
  -v "${html_volume}:/target" \
  -v "${staging}:/staging:ro" \
  alpine:3.22 \
  sh -c 'find /target -mindepth 1 -maxdepth 1 ! -name data -exec rm -rf -- {} + && tar -C /target -xzf /staging/html.tar.gz'

docker compose up --detach --wait --wait-timeout 300 database

# The roles are restored first and without ON_ERROR_STOP: some already exist from
# the PostgreSQL initialization, and those errors are harmless.
gunzip --stdout "$staging/roles.sql.gz" \
  | docker compose exec -T database \
    psql --dbname=postgres --username="$db_user" >/dev/null 2>&1 || true

gunzip --stdout "$staging/database.sql.gz" \
  | docker compose exec -T database \
    psql --dbname="$db_name" --username="$db_user" \
    --single-transaction --set ON_ERROR_STOP=on >/dev/null

docker compose up --detach --wait --wait-timeout 600
docker compose exec -T -u www-data app php occ maintenance:mode --off >/dev/null

echo "Backup restored from: $archive"
echo "The user files directory was left untouched: restore it separately if it was lost."
