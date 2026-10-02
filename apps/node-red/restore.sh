#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f $1 ]]; then
  echo "Usage: $0 path/to/node-red-YYYYMMDDTHHMMSSZ.tar.gz" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
volume="${NODE_RED_DATA_VOLUME:-node-red-data}"

docker run --rm -v "${archive}:/backup.tar.gz:ro" alpine:3.22 \
  sh -c 'tar -tzf /backup.tar.gz >/dev/null'

cd "$script_dir"
# Keep an automatic safety copy before replacing the only persistent volume.
bash "$script_dir/backup.sh"
docker compose stop node-red
restart_node_red() {
  docker compose start node-red >/dev/null
}
trap restart_node_red EXIT

docker run --rm -v "${volume}:/target" -v "${archive}:/backup.tar.gz:ro" alpine:3.22 \
  sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'

echo "Backup restored from: $archive"
