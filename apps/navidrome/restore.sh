#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/navidrome-YYYYMMDDTHHMMSSZ.tar.gz" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$script_dir"

if [[ -f "$script_dir/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$script_dir/.env"
  set +a
fi

volume="${NAVIDROME_DATA_VOLUME:-navidrome-data}"

# A safety copy of the current state before an irreversible replacement.
bash "$script_dir/backup.sh"
docker compose stop navidrome
restart_container() {
  docker compose start navidrome >/dev/null
}
trap restart_container EXIT

docker run --rm \
  -v "${volume}:/target" \
  -v "${archive}:/backup.tar.gz:ro" \
  alpine:3.22 \
  sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'

echo "Backup restored from: $archive"
