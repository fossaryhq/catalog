#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/memos-backup.tar" >&2
  exit 2
fi
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="${FOSSARY_ENV_FILE:-$app_dir/.env}"
[[ -f "$env_file" ]] || { echo "Missing $env_file" >&2; exit 2; }
set -a
# shellcheck disable=SC1091
. "$env_file"
set +a
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-memos}" --env-file "$env_file" --file "$app_dir/compose.yaml")
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

# Validate the complete payload before stopping or replacing the current installation.
tar -C "$staging" -xf "$archive" data.tar.gz config.tar.gz configuration.env compose.yaml
for file in data.tar.gz config.tar.gz configuration.env compose.yaml; do
  [[ -s "$staging/$file" && ! -L "$staging/$file" ]] || { echo "Invalid backup member: $file" >&2; exit 1; }
done
gzip -t "$staging/data.tar.gz" "$staging/config.tar.gz"
tar -tzf "$staging/data.tar.gz" > "$staging/data-files"
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$staging/data-files"; then
  echo "Unsafe data archive paths" >&2
  exit 1
fi
container_id="$("${compose[@]}" ps --all --quiet memos)"
[[ -n "$container_id" ]] || { echo "Start the Memos recipe before restore" >&2; exit 1; }
volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/var/opt/memos"}}{{.Name}}{{end}}{{end}}' "$container_id")"
[[ -n "$volume" ]] || { echo "No named /var/opt/memos volume found" >&2; exit 1; }
bash "$app_dir/backup.sh"
"${compose[@]}" stop memos
docker run --rm -v "$volume:/target" -v "$staging/data.tar.gz:/backup.tar.gz:ro" alpine:3.22 \
  sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'
"${compose[@]}" up -d --wait --wait-timeout 300 memos
echo "Backup restored from: $archive"
echo "Archived configuration.env was not activated. Use matching application versions; compare it and config.tar.gz with active .env and config/."
