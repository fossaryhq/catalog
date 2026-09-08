#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/n8n-YYYYMMDDTHHMMSSZ.tar" >&2
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

data_volume="${N8N_DATA_VOLUME:-n8n-data}"
db_volume="${N8N_DB_VOLUME:-n8n-database}"
db_user="${N8N_DB_USER:-n8n}"
db_name="${N8N_DB_NAME:-n8n}"

# A safety copy of the current state before an irreversible replacement.
bash "$script_dir/backup.sh"

staging="$(mktemp -d)"
cleanup() {
  rm -rf "$staging"
}
trap cleanup EXIT
tar -C "$staging" -xf "$archive" database.sql.gz n8n-data.tar.gz

# The dump is loaded into a clean database, and the data directory is replaced whole.
docker compose down --remove-orphans --timeout 60
docker volume rm --force "$db_volume" >/dev/null
docker run --rm \
  -v "${data_volume}:/target" \
  -v "${staging}:/staging:ro" \
  alpine:3.22 \
  sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /staging/n8n-data.tar.gz'

docker compose up --detach --wait --wait-timeout 300 database

gunzip --stdout "$staging/database.sql.gz" \
  | docker compose exec -T database \
    psql --dbname="$db_name" --username="$db_user" \
    --single-transaction --set ON_ERROR_STOP=on >/dev/null

docker compose up --detach --wait --wait-timeout 600

echo "Backup restored from: $archive"
echo "Make sure N8N_ENCRYPTION_KEY in .env matches the key from the archive, or the credentials will not decrypt."
