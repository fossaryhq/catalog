#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
volume="${NODE_RED_DATA_VOLUME:-node-red-data}"
backup_dir="${NODE_RED_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$backup_dir"
docker compose stop node-red
restart_node_red() {
  docker compose start node-red >/dev/null
}
trap restart_node_red EXIT

docker run --rm -v "${volume}:/source:ro" -v "${backup_dir}:/backup" alpine:3.22 \
  tar -C /source -czf "/backup/node-red-${timestamp}.tar.gz" .

echo "Backup created: $backup_dir/node-red-${timestamp}.tar.gz"
echo "The archive contains flows and encrypted credential data; keep it encrypted."
