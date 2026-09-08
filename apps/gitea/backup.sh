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

data_volume="${GITEA_DATA_VOLUME:-gitea-data}"
db_user="${POSTGRES_USER:-gitea}"
db_name="${POSTGRES_DB:-gitea}"
backup_dir="${GITEA_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
staging="$(mktemp -d)"
mkdir -p "$backup_dir"

restart() {
  rm -rf "$staging"
  docker compose up -d gitea >/dev/null
}
trap restart EXIT

# Gitea must be stopped: the repositories on disk and the database rows that
# describe them are only consistent with each other while nothing writes.
docker compose stop gitea
docker compose exec -T database pg_dump --clean --if-exists --username="$db_user" --dbname="$db_name" | gzip > "$staging/database.sql.gz"
docker run --rm -v "${data_volume}:/source:ro" -v "${staging}:/backup" alpine:3.22 tar -C /source -czf /backup/gitea-data.tar.gz .
archive="$backup_dir/gitea-${timestamp}.tar"
tar -C "$staging" -cf "$archive" database.sql.gz gitea-data.tar.gz

echo "Backup created: $archive"
