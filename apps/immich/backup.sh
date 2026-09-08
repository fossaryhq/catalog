#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

if [[ -f "$script_dir/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$script_dir/.env"
  set +a
fi

upload_location="${IMMICH_UPLOAD_LOCATION:-./library}"
db_username="${IMMICH_DB_USERNAME:-immich}"
db_database_name="${IMMICH_DB_DATABASE_NAME:-immich}"
backup_dir="${IMMICH_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ ! -d "$upload_location" ]]; then
  echo "IMMICH_UPLOAD_LOCATION not found: $upload_location" >&2
  exit 1
fi
upload_path="$(cd "$upload_location" && pwd)"

mkdir -p "$backup_dir"
staging="$(mktemp -d)"

# Only writes are stopped: pg_dump needs the database running.
docker compose stop immich-server immich-machine-learning
cleanup() {
  docker compose start immich-server immich-machine-learning >/dev/null
  rm -rf "$staging"
}
trap cleanup EXIT

# A database dump. Upstream considers copying the PostgreSQL directory unsafe.
docker compose exec -T database \
  pg_dump --clean --if-exists --dbname="$db_database_name" --username="$db_username" \
  | gzip > "$staging/database.sql.gz"

# The library files belong to root inside the container, so the container archives them.
docker run --rm \
  -v "${upload_path}:/source:ro" \
  -v "${staging}:/staging" \
  alpine:3.22 \
  tar -C /source -czf /staging/library.tar.gz .

archive="$backup_dir/immich-${timestamp}.tar"
tar -C "$staging" -cf "$archive" database.sql.gz library.tar.gz

echo "Backup created: $archive"
