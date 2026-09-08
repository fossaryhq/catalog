#!/usr/bin/env bash
set -Eeuo pipefail

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

data_volume="${LINKWARDEN_DATA_VOLUME:-linkwarden-data}"
meili_volume="${LINKWARDEN_MEILI_VOLUME:-linkwarden-meilisearch}"
backup_dir="${LINKWARDEN_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
staging="$(mktemp -d)"
services_stopped=false
cleanup() {
  status=$?
  if [[ "$services_stopped" == true ]]; then
    docker compose start meilisearch linkwarden >/dev/null || true
  fi
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT INT TERM
mkdir -p "$backup_dir"

# Quiesce writes to archived state while PostgreSQL remains available for pg_dump.
docker compose stop linkwarden meilisearch
services_stopped=true
docker compose exec -T postgres pg_dump --clean --if-exists --dbname="${POSTGRES_DB:-linkwarden}" --username="${POSTGRES_USER:-linkwarden}" | gzip > "$staging/database.sql.gz"
docker run --rm -v "${data_volume}:/source:ro" -v "${staging}:/backup" alpine:3.22 tar -C /source -czf /backup/data.tar.gz .
docker run --rm -v "${meili_volume}:/source:ro" -v "${staging}:/backup" alpine:3.22 tar -C /source -czf /backup/meilisearch.tar.gz .
cp -- .env "$staging/configuration.env"
cp -- compose.yaml "$staging/compose.yaml"

archive="$backup_dir/linkwarden-${timestamp}.tar"
tar -C "$staging" -cf "$archive" database.sql.gz data.tar.gz meilisearch.tar.gz configuration.env compose.yaml
echo "Backup created: $archive"
echo "The archive contains saved pages, the database, search data, and secrets; encrypt it and copy it off the server."
