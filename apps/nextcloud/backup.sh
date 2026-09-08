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

html_volume="${NEXTCLOUD_HTML_VOLUME:-nextcloud-html}"
db_user="${NEXTCLOUD_DB_USER:-nextcloud}"
db_name="${NEXTCLOUD_DB_NAME:-nextcloud}"
backup_dir="${NEXTCLOUD_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$backup_dir"
staging="$(mktemp -d)"

# Maintenance mode stops writes while a consistent copy is taken.
docker compose exec -T -u www-data app php occ maintenance:mode --on
leave_maintenance() {
  docker compose exec -T -u www-data app php occ maintenance:mode --off >/dev/null
  rm -rf "$staging"
}
trap leave_maintenance EXIT

# The Nextcloud installer creates a separate oc_<admin> role and the objects
# belong to it. Without dumping the roles the dump will not load into a clean
# database.
docker compose exec -T database \
  pg_dumpall --roles-only --username="$db_user" \
  | gzip > "$staging/roles.sql.gz"

docker compose exec -T database \
  pg_dump --clean --if-exists --dbname="$db_name" --username="$db_user" \
  | gzip > "$staging/database.sql.gz"

# The volume holds config.php, the installed apps, and the code; user data is not
# in the archive — it is a separate directory that can run to terabytes.
docker run --rm \
  -v "${html_volume}:/source:ro" \
  -v "${staging}:/staging" \
  alpine:3.22 \
  tar -C /source --exclude=./data -czf /staging/html.tar.gz .

archive="$backup_dir/nextcloud-${timestamp}.tar"
tar -C "$staging" -cf "$archive" roles.sql.gz database.sql.gz html.tar.gz

echo "Backup created: $archive"
echo "User files are not in the archive: copy NEXTCLOUD_DATA_LOCATION separately, with rsync for instance."
