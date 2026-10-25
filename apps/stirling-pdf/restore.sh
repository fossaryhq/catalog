#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/stirling-pdf-YYYYMMDDTHHMMSS.NNNNNNNNNZ.tar.gz" >&2
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
timestamp="$(date -u +%Y%m%dT%H%M%S.%NZ)"
mkdir -p "$data_path" "$backup_dir"
tar -tzf "$archive" >/dev/null

docker compose stop stirling-pdf
for directory in configs customFiles pipeline tessdata; do
  mkdir -p "$data_path/$directory"
done
data_path="$(cd "$data_path" && pwd)"
backup_dir="$(cd "$backup_dir" && pwd)"
emergency="$backup_dir/stirling-pdf-before-restore-${timestamp}.tar.gz"
# Keep the bind-mounted directories themselves in place across the restore.
docker run --rm -v "${data_path}:/target" -v "${backup_dir}:/backup" -v "${archive}:/restore.tar.gz:ro" alpine:3.22 \
  sh -eu -c 'umask 077
    tar -C /target -czf "/backup/$1" configs customFiles pipeline tessdata
    chown "$2:$3" "/backup/$1"
    for directory in configs customFiles pipeline tessdata; do
      find "/target/$directory" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    done
    tar -C /target -xzf /restore.tar.gz configs customFiles pipeline tessdata' \
  sh "$(basename "$emergency")" "$(id -u)" "$(id -g)"
docker compose up -d --wait

echo "Backup restored from: $archive"
echo "Replaced state was saved to: $emergency"
