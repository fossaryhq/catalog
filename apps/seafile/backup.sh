#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

data_volume="${SEAFILE_DATA_VOLUME:-seafile-data}"
backup_dir="${SEAFILE_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
staging="$(mktemp -d)"
seafile_stopped=false
cleanup() {
  status=$?
  if [[ "$seafile_stopped" == true ]]; then
    "${compose[@]}" start seafile >/dev/null || true
  fi
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT INT TERM
mkdir -p "$backup_dir"

# Seafile splits its state in two: three databases hold accounts, libraries, and
# metadata, while the object store under /shared holds the file blocks. A dump
# without the blocks restores an index pointing at nothing, so both are taken
# with the server stopped.
"${compose[@]}" stop seafile
seafile_stopped=true
"${compose[@]}" exec -T db mariadb-dump --user=root --password="${SEAFILE_DB_ROOT_PASSWORD}" \
  --single-transaction --routines --events \
  --databases ccnet_db seafile_db seahub_db | gzip > "$staging/databases.sql.gz"
docker run --rm -v "${data_volume}:/source:ro" -v "${staging}:/backup" alpine:3.22 tar -C /source -czf /backup/data.tar.gz .
cp -- "$env_file" "$staging/configuration.env"
cp -- compose.yaml "$staging/compose.yaml"

archive="$backup_dir/seafile-${timestamp}.tar"
tar -C "$staging" -cf "$archive" databases.sql.gz data.tar.gz configuration.env compose.yaml
echo "Backup created: $archive"
echo "The archive holds every file block, the databases, and the secrets from .env; encrypt it and copy it off the server."
