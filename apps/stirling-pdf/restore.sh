#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/stirling-pdf-YYYYMMDDTHHMMSSZ.tar.gz" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
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
mkdir -p "$data_path" "$backup_dir"
tar -tzf "$archive" >/dev/null

docker compose stop stirling-pdf
for directory in configs customFiles pipeline tessdata; do
  mkdir -p "$data_path/$directory"
done
emergency="$backup_dir/stirling-pdf-before-restore-${timestamp}.tar.gz"
tar -C "$data_path" -czf "$emergency" configs customFiles pipeline tessdata
rm -rf "$data_path/configs" "$data_path/customFiles" "$data_path/pipeline" "$data_path/tessdata"
tar -C "$data_path" -xzf "$archive" configs customFiles pipeline tessdata
docker compose up -d --wait

echo "Backup restored from: $archive"
echo "Replaced state was saved to: $emergency"
