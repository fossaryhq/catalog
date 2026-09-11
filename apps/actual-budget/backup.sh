#!/usr/bin/env bash
set -Eeuo pipefail

# The archive carries every budget file, the server password hash and .env
# itself, so nothing this script writes may be readable by another account on
# the server.
umask 077

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

data_volume="${ACTUAL_DATA_VOLUME:-actual-data}"
backup_dir="${ACTUAL_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
staging="$(mktemp -d)"
actual_stopped=false
cleanup() {
  status=$?
  if [[ "$actual_stopped" == true ]]; then
    "${compose[@]}" start actual >/dev/null || true
  fi
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT INT TERM
mkdir -p "$backup_dir"

# Actual keeps SQLite files under /data: account.sqlite with the server password
# and the session, plus one database per budget. They are copied with the server
# stopped, because a live SQLite file can be archived mid-write.
"${compose[@]}" stop actual
actual_stopped=true
docker run --rm -v "${data_volume}:/source:ro" -v "${staging}:/backup" alpine:3.22 tar -C /source -czf /backup/data.tar.gz .
cp -- "$env_file" "$staging/configuration.env"
cp -- compose.yaml "$staging/compose.yaml"

archive="$backup_dir/actual-budget-${timestamp}.tar"
tar -C "$staging" -cf "$archive" data.tar.gz configuration.env compose.yaml
echo "Backup created: $archive"
echo "This archive holds every budget file and the server password hash; encrypt it and copy it off the server."
