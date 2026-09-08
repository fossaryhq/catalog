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

backup_dir="${MINIFLUX_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
staging="$(mktemp -d)"
miniflux_stopped=false
cleanup() {
  status=$?
  if [[ "$miniflux_stopped" == true ]]; then
    "${compose[@]}" start miniflux >/dev/null || true
  fi
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT INT TERM
mkdir -p "$backup_dir"

# Miniflux keeps everything in PostgreSQL — feeds, entries, icons, sessions and
# API keys — so one consistent dump is the whole state. The application is
# stopped first so no poller writes during the dump.
"${compose[@]}" stop miniflux
miniflux_stopped=true
"${compose[@]}" exec -T database pg_dump --clean --if-exists --dbname="${MINIFLUX_DB_NAME:-miniflux}" --username="${MINIFLUX_DB_USER:-miniflux}" | gzip > "$staging/database.sql.gz"
cp -- "$env_file" "$staging/configuration.env"
cp -- compose.yaml "$staging/compose.yaml"

archive="$backup_dir/miniflux-${timestamp}.tar"
tar -C "$staging" -cf "$archive" database.sql.gz configuration.env compose.yaml
echo "Backup created: $archive"
echo "An OPML export lists subscriptions only. This archive holds every entry, icon, session, and secret; encrypt it and copy it off the server."
