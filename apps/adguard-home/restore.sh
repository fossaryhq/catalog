#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/adguard-home-backup.tar.gz" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
conf_volume="${ADGUARD_CONF_VOLUME:-adguard-home-conf}"
work_volume="${ADGUARD_WORK_VOLUME:-adguard-home-work}"

cd "$script_dir"
# A safety copy of the current state before the data is replaced.
bash "$script_dir/backup.sh"
docker compose stop adguard-home
restart_container() {
  docker compose start adguard-home >/dev/null
}
trap restart_container EXIT

docker run --rm \
  -v "${conf_volume}:/target/conf" \
  -v "${work_volume}:/target/work" \
  -v "${archive}:/backup.tar.gz:ro" \
  alpine:3.22 \
  sh -c 'find /target/conf /target/work -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'

echo "Backup restored from: $archive"
