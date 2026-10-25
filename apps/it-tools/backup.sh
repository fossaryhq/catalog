#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="${FOSSARY_ENV_FILE:-$app_dir/.env}"
[[ -f "$env_file" ]] || { echo "Missing $env_file" >&2; exit 2; }
set -a
# shellcheck disable=SC1090,SC1091
. "$env_file"
set +a
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-it-tools}" --env-file "$env_file" --file "$app_dir/compose.yaml")
backup_dir="${IT_TOOLS_BACKUP_DIR:-$app_dir/backups}"
mkdir -p "$backup_dir"
backup_dir="$(cd "$backup_dir" && pwd)"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R config "$staging/config"
cp -- "$env_file" "$staging/configuration.env"
cp compose.yaml "$staging/compose.yaml"
archive="$backup_dir/it-tools-$(date -u +%Y%m%dT%H%M%S.%NZ).tar.gz"
tar -C "$staging" -czf "$archive" config configuration.env compose.yaml
echo "Configuration backup: $archive"
echo 'Browser favorites, input history, language and theme are not server data and are not in this archive. Keep your browser profile separately.'
