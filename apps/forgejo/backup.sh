#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
backup_dir="${FORGEJO_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
staging="$(mktemp -d)"
mkdir -p "$backup_dir"

restart() {
  rm -rf "$staging"
  docker compose up -d forgejo >/dev/null
}
trap restart EXIT

docker compose stop forgejo
docker compose exec -T database pg_dump --clean --if-exists --username="$db_user" --dbname="$db_name" | gzip > "$staging/database.sql.gz"
docker run --rm -v "${data_volume}:/source:ro" -v "${staging}:/backup" alpine:3.22 tar -C /source -czf /backup/forgejo-data.tar.gz .
archive="$backup_dir/forgejo-${timestamp}.tar"
tar -C "$staging" -cf "$archive" database.sql.gz forgejo-data.tar.gz

echo "Backup created: $archive"
