#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
if [[ ! -f .env ]]; then
  echo "Missing $script_dir/.env" >&2
  exit 2
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a

data_path="${STIRLING_PDF_DATA_PATH:-$script_dir/data}"
backup_dir="${STIRLING_PDF_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"
for directory in configs customFiles pipeline tessdata; do
  mkdir -p "$data_path/$directory"
done

restart() {
  docker compose start stirling-pdf >/dev/null
}
trap restart EXIT
docker compose stop stirling-pdf
archive="$backup_dir/stirling-pdf-${timestamp}.tar.gz"
tar -C "$data_path" -czf "$archive" configs customFiles pipeline tessdata

echo "Backup created: $archive"
echo "The archive contains the H2 user database and sensitive settings; encrypt it and copy it off the server."
