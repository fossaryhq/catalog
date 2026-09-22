#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

volume="${GATUS_DATA_VOLUME:-gatus-data}"
config_dir="${GATUS_CONFIG_DIR:-$script_dir/config}"
backup_dir="${GATUS_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%S.%NZ)"
case "$config_dir" in
  /*) ;;
  *) config_dir="$script_dir/${config_dir#./}" ;;
esac

mkdir -p "$backup_dir"

docker compose stop gatus
restart_container() {
  docker compose start gatus >/dev/null
}
trap restart_container EXIT

docker run --rm \
  -v "${volume}:/source/data:ro" \
  -v "${config_dir}:/source/config:ro" \
  -v "${backup_dir}:/backup" \
  alpine:3.22 \
  tar -C /source -czf "/backup/gatus-${timestamp}.tar.gz" data config

echo "Backup created: $backup_dir/gatus-${timestamp}.tar.gz"
