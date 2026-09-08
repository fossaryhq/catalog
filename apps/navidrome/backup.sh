#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

if [[ -f "$script_dir/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$script_dir/.env"
  set +a
fi

volume="${NAVIDROME_DATA_VOLUME:-navidrome-data}"
backup_dir="${NAVIDROME_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$backup_dir"

# The SQLite database only copies consistently from a stopped server.
docker compose stop navidrome
restart_container() {
  docker compose start navidrome >/dev/null
}
trap restart_container EXIT

docker run --rm \
  -v "${volume}:/source:ro" \
  -v "${backup_dir}:/backup" \
  alpine:3.22 \
  tar -C /source -czf "/backup/navidrome-${timestamp}.tar.gz" .

echo "Backup created: $backup_dir/navidrome-${timestamp}.tar.gz"
echo "The music library is not in the archive: copy NAVIDROME_MUSIC_LOCATION separately."
