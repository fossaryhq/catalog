#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/linkwarden-YYYYMMDDTHHMMSSZ.tar" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$script_dir"
if [[ ! -f .env ]]; then
  echo "Missing $script_dir/.env" >&2
  exit 2
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a

data_volume="${LINKWARDEN_DATA_VOLUME:-linkwarden-data}"
db_volume="${LINKWARDEN_DB_VOLUME:-linkwarden-postgres}"
meili_volume="${LINKWARDEN_MEILI_VOLUME:-linkwarden-meilisearch}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -C "$staging" -xf "$archive" database.sql.gz data.tar.gz meilisearch.tar.gz configuration.env compose.yaml

# Preserve the state that will be irreversibly replaced.
bash "$script_dir/backup.sh"
docker compose down --remove-orphans --timeout 60
docker volume rm --force "$data_volume" "$db_volume" "$meili_volume" >/dev/null
docker volume create "$data_volume" >/dev/null
docker volume create "$meili_volume" >/dev/null
docker run --rm -v "${data_volume}:/target" -v "${staging}:/restore:ro" alpine:3.22 tar -C /target -xzf /restore/data.tar.gz
docker run --rm -v "${meili_volume}:/target" -v "${staging}:/restore:ro" alpine:3.22 tar -C /target -xzf /restore/meilisearch.tar.gz

docker compose up --detach --wait --wait-timeout 300 postgres
gunzip -c "$staging/database.sql.gz" | docker compose exec -T postgres psql --set ON_ERROR_STOP=1 --dbname="${POSTGRES_DB:-linkwarden}" --username="${POSTGRES_USER:-linkwarden}"
docker compose up --detach --wait --wait-timeout 600 meilisearch linkwarden

echo "Backup restored from: $archive"
echo "The archived configuration.env was not activated. Compare it with .env and keep all archived versions until verification."
