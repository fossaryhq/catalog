#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/forgejo-YYYYMMDDTHHMMSSZ.tar" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$script_dir"
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

data_volume="${FORGEJO_DATA_VOLUME:-forgejo-data}"
db_user="${POSTGRES_USER:-forgejo}"
db_name="${POSTGRES_DB:-forgejo}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -C "$staging" -xf "$archive" database.sql.gz forgejo-data.tar.gz

# Keep an emergency copy of the state that is about to be replaced.
bash "$script_dir/backup.sh"
docker compose stop forgejo
docker run --rm -v "${data_volume}:/target" -v "${staging}:/restore:ro" alpine:3.22 sh -c 'rm -rf /target/* /target/.[!.]* /target/..?* 2>/dev/null || true; tar -C /target -xzf /restore/forgejo-data.tar.gz'
gunzip --stdout "$staging/database.sql.gz" | docker compose exec -T database psql --username="$db_user" --dbname="$db_name" --single-transaction --set ON_ERROR_STOP=on >/dev/null
docker compose up -d --wait

echo "Backup restored from: $archive"
