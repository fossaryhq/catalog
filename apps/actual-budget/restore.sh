#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/actual-budget-YYYYMMDDTHHMMSSZ.tar" >&2
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

data_volume="${ACTUAL_DATA_VOLUME:-actual-data}"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
tar -C "$staging" -xf "$archive" data.tar.gz configuration.env compose.yaml

# Preserve the state that will be irreversibly replaced.
bash "$script_dir/backup.sh"
"${compose[@]}" down --remove-orphans --timeout 60
docker volume rm --force "$data_volume" >/dev/null
docker volume create "$data_volume" >/dev/null
docker run --rm -v "${data_volume}:/target" -v "${staging}:/restore:ro" alpine:3.22 tar -C /target -xzf /restore/data.tar.gz
"${compose[@]}" up --detach --wait --wait-timeout 300

echo "Backup restored from: $archive"
echo "The archived configuration.env was not activated. Compare it with .env, and re-sync every client: a restored server is older than the local copies in browsers and desktop apps."
