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

volume="${SYNCTHING_CONFIG_VOLUME:-syncthing-config}"
backup_dir="${SYNCTHING_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$backup_dir"

# The device keys and the index database only copy consistently from a stopped node.
docker compose stop syncthing
restart_container() {
  docker compose start syncthing >/dev/null
}
trap restart_container EXIT

docker run --rm \
  -v "${volume}:/source:ro" \
  -v "${backup_dir}:/backup" \
  alpine:3.22 \
  tar -C /source -czf "/backup/syncthing-${timestamp}.tar.gz" .

echo "Backup created: $backup_dir/syncthing-${timestamp}.tar.gz"
echo "The archive holds the device private key: encrypt it before it leaves the server."
echo "The synchronised files are not in the archive: copy SYNCTHING_DATA_LOCATION separately."
