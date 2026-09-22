#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/gatus-backup.tar.gz" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
volume="${GATUS_DATA_VOLUME:-gatus-data}"
config_dir="${GATUS_CONFIG_DIR:-$script_dir/config}"
case "$config_dir" in
  /*) ;;
  *) config_dir="$script_dir/${config_dir#./}" ;;
esac

docker run --rm -v "${archive}:/backup.tar.gz:ro" alpine:3.22 \
  sh -c 'tar -tzf /backup.tar.gz | grep -qx "config/config.yaml" && tar -tzf /backup.tar.gz | grep -q "^data/"'

cd "$script_dir"
bash "$script_dir/backup.sh"
docker compose stop gatus
restart_container() {
  docker compose start gatus >/dev/null
}
trap restart_container EXIT

docker run --rm \
  -v "${volume}:/target/data" \
  -v "${config_dir}:/target/config" \
  -v "${archive}:/backup.tar.gz:ro" \
  alpine:3.22 \
  sh -c 'find /target/data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && find /target/config -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'

echo "Backup restored from: $archive"
