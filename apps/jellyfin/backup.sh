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

volume="${JELLYFIN_CONFIG_VOLUME:-jellyfin-config}"
backup_dir="${JELLYFIN_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$backup_dir"

# Upstream requires a stopped server: that is the only way SQLite copies consistently.
docker compose stop jellyfin
restart_container() {
  docker compose start jellyfin >/dev/null
}
trap restart_container EXIT

docker run --rm \
  -v "${volume}:/source:ro" \
  -v "${backup_dir}:/backup" \
  alpine:3.22 \
  tar -C /source -czf "/backup/jellyfin-${timestamp}.tar.gz" .

echo "Backup created: $backup_dir/jellyfin-${timestamp}.tar.gz"
echo "The media library is not in the archive: copy JELLYFIN_MEDIA_LOCATION separately."
