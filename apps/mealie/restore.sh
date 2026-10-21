#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/mealie-backup.tar.gz" >&2
  exit 2
fi
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
env_file="$app_dir/.env.example"
if [[ -f "$app_dir/.env" ]]; then
  env_file="$app_dir/.env"
  set -a
  # shellcheck disable=SC1091
  . "$env_file"
  set +a
fi
project="${COMPOSE_PROJECT_NAME:-mealie}"
volume="${MEALIE_DATA_VOLUME:-mealie-data}"
compose=(docker compose --project-name "$project" --env-file "$env_file" --file "$app_dir/compose.yaml")

# Preserve the current state before the destructive replacement.
bash "$app_dir/backup.sh"
"${compose[@]}" stop mealie
restart_container() { "${compose[@]}" start mealie >/dev/null; }
trap restart_container EXIT
if tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  echo "Unsafe archive paths; restore aborted" >&2
  exit 1
fi
docker run --rm -v "${volume}:/target" -v "$archive:/backup.tar.gz:ro" alpine:3.22 \
  sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'
echo "Backup restored from: $archive"
