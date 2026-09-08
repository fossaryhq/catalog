#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

conf_volume="${ADGUARD_CONF_VOLUME:-adguard-home-conf}"
work_volume="${ADGUARD_WORK_VOLUME:-adguard-home-work}"
backup_dir="${ADGUARD_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%S.%NZ)"

mkdir -p "$backup_dir"

docker compose stop adguard-home
restart_container() {
  docker compose start adguard-home >/dev/null
}
trap restart_container EXIT

# Both volumes go into one archive: configuration without statistics, or the
# other way round, restores into an inconsistent pair.
docker run --rm \
  -v "${conf_volume}:/source/conf:ro" \
  -v "${work_volume}:/source/work:ro" \
  -v "${backup_dir}:/backup" \
  alpine:3.22 \
  tar -C /source -czf "/backup/adguard-home-${timestamp}.tar.gz" conf work

echo "Backup created: $backup_dir/adguard-home-${timestamp}.tar.gz"
