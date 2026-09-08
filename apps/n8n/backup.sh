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

data_volume="${N8N_DATA_VOLUME:-n8n-data}"
db_user="${N8N_DB_USER:-n8n}"
db_name="${N8N_DB_NAME:-n8n}"
backup_dir="${N8N_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$backup_dir"
staging="$(mktemp -d)"

# n8n is stopped for the copy so that the database dump and the data directory
# describe the same state. The database stays up for pg_dump.
docker compose stop n8n
restart_n8n() {
  docker compose start n8n >/dev/null
  rm -rf "$staging"
}
trap restart_n8n EXIT

docker compose exec -T database \
  pg_dump --clean --if-exists --dbname="$db_name" --username="$db_user" \
  | gzip > "$staging/database.sql.gz"

# The volume holds the encryption key from the config and the binary execution
# data. Without the key the dump is useless: the credentials stay encrypted.
docker run --rm \
  -v "${data_volume}:/source:ro" \
  -v "${staging}:/staging" \
  alpine:3.22 \
  tar -C /source -czf /staging/n8n-data.tar.gz .

archive="$backup_dir/n8n-${timestamp}.tar"
tar -C "$staging" -cf "$archive" database.sql.gz n8n-data.tar.gz

echo "Backup created: $archive"
echo "The archive holds the encryption key and access to every connected service: treat it as a password."
