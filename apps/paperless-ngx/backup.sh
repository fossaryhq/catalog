#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
if [[ ! -f .env ]]; then
  echo "Missing $script_dir/.env" >&2
  exit 2
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a

export_volume="${PAPERLESS_EXPORT_VOLUME:-paperless-export}"
consume_volume="${PAPERLESS_CONSUME_VOLUME:-paperless-consume}"
backup_dir="${PAPERLESS_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$backup_dir"

# Wait for current consumption tasks and leave consume empty before running this.
docker compose exec -T webserver document_exporter ../export --delete --no-progress-bar
docker run --rm -v "${export_volume}:/source:ro" -v "${staging}:/backup" alpine:3.22 tar -C /source -czf /backup/export.tar.gz .
docker run --rm -v "${consume_volume}:/source:ro" -v "${staging}:/backup" alpine:3.22 tar -C /source -czf /backup/consume.tar.gz .
cp -- .env "$staging/configuration.env"
cp -- compose.yaml "$staging/compose.yaml"

archive="$backup_dir/paperless-ngx-${timestamp}.tar"
tar -C "$staging" -cf "$archive" export.tar.gz consume.tar.gz configuration.env compose.yaml

echo "Backup created: $archive"
echo "The archive contains documents, users, and secrets; encrypt it and copy it off the server. API tokens are not exported."
