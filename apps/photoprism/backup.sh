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

originals="${PHOTOPRISM_ORIGINALS_PATH:-$script_dir/originals}"
storage="${PHOTOPRISM_STORAGE_PATH:-$script_dir/storage}"
db_name="${PHOTOPRISM_DATABASE_NAME:-photoprism}"
db_root_password="${PHOTOPRISM_DATABASE_ROOT_PASSWORD:?PHOTOPRISM_DATABASE_ROOT_PASSWORD must be set in .env}"
backup_dir="${PHOTOPRISM_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
staging="$(mktemp -d)"
mkdir -p "$backup_dir"

restart() {
  rm -rf "$staging"
  docker compose up -d photoprism >/dev/null
}
trap restart EXIT

# PhotoPrism must be stopped: an index running during the copy would leave the
# database describing files that the originals archive does not contain.
docker compose stop photoprism
# The password travels in MYSQL_PWD, not argv, so it stays out of the container
# process list.
docker compose exec -T --env MYSQL_PWD="$db_root_password" mariadb \
  mariadb-dump --user=root --single-transaction --routines --events "$db_name" | gzip > "$staging/database.sql.gz"
tar -C "$originals" -czf "$staging/photoprism-originals.tar.gz" .
tar -C "$storage" -czf "$staging/photoprism-storage.tar.gz" .
archive="$backup_dir/photoprism-${timestamp}.tar"
tar -C "$staging" -cf "$archive" database.sql.gz photoprism-originals.tar.gz photoprism-storage.tar.gz

echo "Backup created: $archive"
