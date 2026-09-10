#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

volume="${VAULTWARDEN_DATA_VOLUME:-vaultwarden-data}"
backup_dir="${VAULTWARDEN_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%S.%NZ)"

mkdir -p "$backup_dir"

docker compose stop vaultwarden
restart_container() {
  docker compose start vaultwarden >/dev/null
}
trap restart_container EXIT

docker run --rm \
  -v "${volume}:/source:ro" \
  -v "${backup_dir}:/backup" \
  alpine:3.22 \
  sh -c "umask 077 && tar -C /source -czf '/backup/vaultwarden-${timestamp}.tar.gz' ."

echo "Backup created: $backup_dir/vaultwarden-${timestamp}.tar.gz"
