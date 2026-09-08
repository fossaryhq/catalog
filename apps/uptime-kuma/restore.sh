#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/uptime-kuma-backup.tar.gz" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
volume="${UPTIME_KUMA_DATA_VOLUME:-uptime-kuma-data}"

cd "$script_dir"
bash "$script_dir/backup.sh"
docker compose stop uptime-kuma
restart_container() {
  docker compose start uptime-kuma >/dev/null
}
trap restart_container EXIT

docker run --rm \
  -v "${volume}:/target" \
  -v "${archive}:/backup.tar.gz:ro" \
  alpine:3.22 \
  sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'

echo "Backup restored from: $archive"
