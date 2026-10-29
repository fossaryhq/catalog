#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $# -eq 1 && -f "$1" ]] || { echo "Usage: $0 path/to/karakeep-backup.tar" >&2; exit 2; }
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="${FOSSARY_ENV_FILE:-$app_dir/.env}"
[[ -f "$env_file" ]] || { echo "Missing $env_file" >&2; exit 2; }
set -a
# shellcheck disable=SC1090
. "$env_file"
set +a
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-karakeep}" --env-file "$env_file" --file "$app_dir/compose.yaml")
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
# Reject incomplete archives before creating a safety backup or replacing data.
tar -C "$staging" -xf "$archive" volume-0.tar.gz volume-1.tar.gz configuration.env compose.yaml
for file in volume-0.tar.gz volume-1.tar.gz configuration.env compose.yaml; do
  [[ -s "$staging/$file" && ! -L "$staging/$file" ]] || { echo "Invalid backup member: $file" >&2; exit 1; }
done
for index in 0 1; do
  gzip -t "$staging/volume-$index.tar.gz"
  tar -tzf "$staging/volume-$index.tar.gz" > "$staging/paths"
  if grep -Eq '(^/|(^|/)\.\.(/|$))' "$staging/paths"; then echo "Unsafe archive path" >&2; exit 1; fi
done
volumes=()
for spec in karakeep:/data meilisearch:/meili_data; do
  service="${spec%%:*}"
  mount="${spec#*:}"
  id="$("${compose[@]}" ps --all --quiet "$service")"
  [[ -n "$id" ]] || { echo "Create the Karakeep containers before restore" >&2; exit 1; }
  volume="$(docker inspect --format "{{range .Mounts}}{{if eq .Destination \"$mount\"}}{{.Name}}{{end}}{{end}}" "$id")"
  [[ -n "$volume" ]] || { echo "Missing named volume at $mount" >&2; exit 1; }
  volumes+=("$volume")
done
bash "$app_dir/backup.sh"
"${compose[@]}" stop karakeep meilisearch
for index in 0 1; do
  docker run --rm -v "${volumes[$index]}:/target" -v "$staging/volume-$index.tar.gz:/backup.tar.gz:ro" alpine:3.22.2 \
    sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'
done
"${compose[@]}" up -d --wait --wait-timeout 600
echo "Restored: $archive"
echo "Archived configuration.env was not activated. Use matching application and Meilisearch versions and secrets."
