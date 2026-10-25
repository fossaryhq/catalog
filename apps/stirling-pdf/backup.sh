#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

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
timestamp="$(date -u +%Y%m%dT%H%M%S.%NZ)"
mkdir -p "$backup_dir"
for directory in configs customFiles pipeline tessdata; do
  mkdir -p "$data_path/$directory"
done
data_path="$(cd "$data_path" && pwd)"
backup_dir="$(cd "$backup_dir" && pwd)"

restart() {
  docker compose start stirling-pdf >/dev/null
}
trap restart EXIT
docker compose stop stirling-pdf
archive="$backup_dir/stirling-pdf-${timestamp}.tar.gz"
docker run --rm -v "${data_path}:/source:ro" -v "${backup_dir}:/backup" alpine:3.22 \
  sh -eu -c 'umask 077; tar -C /source -czf "/backup/$1" configs customFiles pipeline tessdata; chown "$2:$3" "/backup/$1"' \
  sh "$(basename "$archive")" "$(id -u)" "$(id -g)"

echo "Backup created: $archive"
echo "The archive contains the H2 user database and sensitive settings; encrypt it and copy it off the server."
