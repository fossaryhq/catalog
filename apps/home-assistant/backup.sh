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

volume="${HOMEASSISTANT_CONFIG_VOLUME:-home-assistant-config}"
backup_dir="${HOMEASSISTANT_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$backup_dir"

# The states live in SQLite, and a copy taken from a running server comes out
# inconsistent, so the container is stopped for the duration of the archive.
docker compose stop home-assistant
restart_container() {
  docker compose start home-assistant >/dev/null
}
trap restart_container EXIT

docker run --rm \
  -v "${volume}:/source:ro" \
  -v "${backup_dir}:/backup" \
  alpine:3.22 \
  tar -C /source -czf "/backup/home-assistant-${timestamp}.tar.gz" .

echo "Backup created: $backup_dir/home-assistant-${timestamp}.tar.gz"
echo "The archive holds access tokens and integration credentials: keep it off this server and somewhere protected."
