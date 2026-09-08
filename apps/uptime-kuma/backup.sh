#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

volume="${UPTIME_KUMA_DATA_VOLUME:-uptime-kuma-data}"
backup_dir="${UPTIME_KUMA_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%S.%NZ)"

mkdir -p "$backup_dir"

docker compose stop uptime-kuma
restart_container() {
  docker compose start uptime-kuma >/dev/null
}
trap restart_container EXIT

docker run --rm \
  -v "${volume}:/source:ro" \
  -v "${backup_dir}:/backup" \
  alpine:3.22 \
  tar -C /source -czf "/backup/uptime-kuma-${timestamp}.tar.gz" .

echo "Backup created: $backup_dir/uptime-kuma-${timestamp}.tar.gz"
