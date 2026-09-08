#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/photoprism-YYYYMMDDTHHMMSSZ.tar" >&2
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

originals="${PHOTOPRISM_ORIGINALS_PATH:-$script_dir/originals}"
storage="${PHOTOPRISM_STORAGE_PATH:-$script_dir/storage}"
db_name="${PHOTOPRISM_DATABASE_NAME:-photoprism}"
db_user="${PHOTOPRISM_DATABASE_USER:-photoprism}"
db_root_password="${PHOTOPRISM_DATABASE_ROOT_PASSWORD:?PHOTOPRISM_DATABASE_ROOT_PASSWORD must be set in .env}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -C "$staging" -xf "$archive" database.sql.gz photoprism-originals.tar.gz photoprism-storage.tar.gz

# Keep an emergency copy of the state that is about to be replaced.
bash "$script_dir/backup.sh"
docker compose stop photoprism

# Both directories are bind mounts on the host, so they are emptied in place.
# The `:?` guards stop the delete from ever running against an unset path.
find "${originals:?}" -mindepth 1 -delete
find "${storage:?}" -mindepth 1 -delete
tar -C "$originals" -xzf "$staging/photoprism-originals.tar.gz"
tar -C "$storage" -xzf "$staging/photoprism-storage.tar.gz"

docker compose up -d --wait mariadb
docker compose exec -T --env MYSQL_PWD="$db_root_password" mariadb mariadb --user=root --execute="\
DROP DATABASE IF EXISTS \`${db_name}\`; \
CREATE DATABASE \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
GRANT ALL ON \`${db_name}\`.* TO '${db_user}'@'%';"
gunzip --stdout "$staging/database.sql.gz" | docker compose exec -T --env MYSQL_PWD="$db_root_password" mariadb mariadb --user=root "$db_name"
docker compose up -d --wait

echo "Backup restored from: $archive"
