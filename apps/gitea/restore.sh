#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/gitea-YYYYMMDDTHHMMSSZ.tar" >&2
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

data_volume="${GITEA_DATA_VOLUME:-gitea-data}"
db_user="${POSTGRES_USER:-gitea}"
db_name="${POSTGRES_DB:-gitea}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -C "$staging" -xf "$archive" database.sql.gz gitea-data.tar.gz

# Keep an emergency copy of the state that is about to be replaced.
bash "$script_dir/backup.sh"
docker compose stop gitea
docker run --rm -v "${data_volume}:/target" -v "${staging}:/restore:ro" alpine:3.22 sh -c 'rm -rf /target/* /target/.[!.]* /target/..?* 2>/dev/null || true; tar -C /target -xzf /restore/gitea-data.tar.gz'
gunzip --stdout "$staging/database.sql.gz" | docker compose exec -T database psql --username="$db_user" --dbname="$db_name" --single-transaction --set ON_ERROR_STOP=on >/dev/null
docker compose up -d --wait
# Hook scripts embed absolute paths and the binary version, so they are
# rewritten after the data directory is replaced. The binary refuses to run as
# root, so the command goes in as the image's own `git` user.
docker compose exec -T --user git gitea gitea admin regenerate hooks

echo "Backup restored from: $archive"
