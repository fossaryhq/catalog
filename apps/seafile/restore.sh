#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/seafile-YYYYMMDDTHHMMSSZ.tar" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$script_dir"
env_file="${FOSSARY_ENV_FILE:-$script_dir/.env}"
if [[ ! -e "$env_file" ]]; then
  echo "Missing $env_file" >&2
  exit 2
fi
set -a
# shellcheck disable=SC1091
. "$env_file"
set +a
compose=(docker compose --env-file "$env_file")

data_volume="${SEAFILE_DATA_VOLUME:-seafile-data}"
db_volume="${SEAFILE_DB_VOLUME:-seafile-database}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -C "$staging" -xf "$archive" databases.sql.gz data.tar.gz configuration.env compose.yaml

# Preserve the state that will be irreversibly replaced.
bash "$script_dir/backup.sh"
"${compose[@]}" down --remove-orphans --timeout 120
docker volume rm --force "$data_volume" "$db_volume" >/dev/null
docker volume create "$data_volume" >/dev/null
docker run --rm -v "${data_volume}:/target" -v "${staging}:/restore:ro" alpine:3.22 tar -C /target -xzf /restore/data.tar.gz

"${compose[@]}" up --detach --wait --wait-timeout 300 db
gunzip -c "$staging/databases.sql.gz" | "${compose[@]}" exec -T db mariadb --user=root --password="${SEAFILE_DB_ROOT_PASSWORD}"
escaped_user="${SEAFILE_DB_USER:-seafile}"
escaped_user="${escaped_user//\'/\'\'}"
escaped_password="${SEAFILE_DB_PASSWORD//\'/\'\'}"
"${compose[@]}" exec -T db mariadb --user=root --password="${SEAFILE_DB_ROOT_PASSWORD}" --execute="
  CREATE USER IF NOT EXISTS '${escaped_user}'@'%' IDENTIFIED BY '${escaped_password}';
  GRANT ALL PRIVILEGES ON ccnet_db.* TO '${escaped_user}'@'%';
  GRANT ALL PRIVILEGES ON seafile_db.* TO '${escaped_user}'@'%';
  GRANT ALL PRIVILEGES ON seahub_db.* TO '${escaped_user}'@'%';
  FLUSH PRIVILEGES;"
"${compose[@]}" up --detach --wait --wait-timeout 900 seafile

echo "Backup restored from: $archive"
echo "The archived configuration.env was not activated. Compare it with .env and keep Seafile at the archived version until the restore is verified."
