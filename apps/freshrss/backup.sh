#!/usr/bin/env bash
set -Eeuo pipefail

# The archive carries the database, every data file and .env itself, so nothing
# this script writes may be readable by another account on the server.
umask 077

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
backup_dir="${FRESHRSS_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
staging="$(mktemp -d)"
freshrss_stopped=false
cleanup() {
  status=$?
  if [[ "$freshrss_stopped" == true ]]; then
    docker compose start freshrss >/dev/null || true
  fi
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT INT TERM
mkdir -p "$backup_dir"

# Stop web requests and built-in cron while keeping PostgreSQL available for pg_dump.
docker compose stop freshrss
freshrss_stopped=true
docker compose exec -T database pg_dump --clean --if-exists --dbname="${FRESHRSS_DB_NAME:-freshrss}" --username="${FRESHRSS_DB_USER:-freshrss}" | gzip > "$staging/database.sql.gz"
docker run --rm -v "${data_volume}:/source:ro" -v "${staging}:/backup" alpine:3.22 tar -C /source -czf /backup/data.tar.gz .
docker run --rm -v "${extensions_volume}:/source:ro" -v "${staging}:/backup" alpine:3.22 tar -C /source -czf /backup/extensions.tar.gz .
cp -- .env "$staging/configuration.env"
cp -- compose.yaml "$staging/compose.yaml"

archive="$backup_dir/freshrss-${timestamp}.tar"
tar -C "$staging" -cf "$archive" database.sql.gz data.tar.gz extensions.tar.gz configuration.env compose.yaml
echo "Backup created: $archive"
echo "OPML alone is incomplete. This archive contains the database, all data, extensions, and secrets; encrypt it and copy it off the server."
