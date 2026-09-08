#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/paperless-ngx-YYYYMMDDTHHMMSSZ.tar" >&2
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

data_volume="${PAPERLESS_DATA_VOLUME:-paperless-data}"
media_volume="${PAPERLESS_MEDIA_VOLUME:-paperless-media}"
export_volume="${PAPERLESS_EXPORT_VOLUME:-paperless-export}"
consume_volume="${PAPERLESS_CONSUME_VOLUME:-paperless-consume}"
db_volume="${PAPERLESS_DB_VOLUME:-paperless-database}"
broker_volume="${PAPERLESS_BROKER_VOLUME:-paperless-broker}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -C "$staging" -xf "$archive" export.tar.gz consume.tar.gz configuration.env compose.yaml

# Preserve the state about to be replaced. This also refreshes the export.
bash "$script_dir/backup.sh"
docker compose down --remove-orphans --timeout 60
docker volume rm --force "$data_volume" "$media_volume" "$export_volume" "$consume_volume" "$db_volume" "$broker_volume" >/dev/null
docker run --rm -v "${export_volume}:/target" -v "${staging}:/restore:ro" alpine:3.22 tar -C /target -xzf /restore/export.tar.gz
docker run --rm -v "${consume_volume}:/target" -v "${staging}:/restore:ro" alpine:3.22 tar -C /target -xzf /restore/consume.tar.gz

# Paperless must initialize an empty database before importing the same-version export.
docker compose up --detach --wait --wait-timeout 600
docker compose exec -T webserver document_importer ../export --no-progress-bar

echo "Backup restored from: $archive"
echo "The archived configuration.env was not activated. Compare it with .env, keep Paperless at the exported version, and issue new API tokens."
