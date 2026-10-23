#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $# -eq 1 && -f "$1" ]] || { echo "Usage: $0 path/to/open-webui-backup.tar" >&2; exit 2; }
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="${FOSSARY_ENV_FILE:-$app_dir/.env}"
[[ -f "$env_file" ]] || { echo "Missing $env_file" >&2; exit 2; }
set -a
# shellcheck disable=SC1091
. "$env_file"
set +a
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-open-webui}" --env-file "$env_file" --file "$app_dir/compose.yaml")
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
# Refuse an incomplete payload before stopping or changing the current installation.
tar -C "$staging" -xf "$archive" webui.tar.gz models.tar.gz configuration.env compose.yaml
for file in webui.tar.gz models.tar.gz configuration.env compose.yaml; do
  [[ -s "$staging/$file" && ! -L "$staging/$file" ]] || { echo "Invalid backup member: $file" >&2; exit 1; }
done
for file in webui models; do
  gzip -t "$staging/$file.tar.gz"
  tar -tzf "$staging/$file.tar.gz" > "$staging/$file-files"
  if grep -Eq '(^/|(^|/)\.\.(/|$))' "$staging/$file-files"; then echo 'Unsafe archive paths' >&2; exit 1; fi
done
webui_id="$("${compose[@]}" ps --all --quiet open-webui)"
ollama_id="$("${compose[@]}" ps --all --quiet ollama)"
[[ -n "$webui_id" && -n "$ollama_id" ]] || { echo 'Start the recipe before restore' >&2; exit 1; }
webui_volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/backend/data"}}{{.Name}}{{end}}{{end}}' "$webui_id")"
models_volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/home/ollama/.ollama"}}{{.Name}}{{end}}{{end}}' "$ollama_id")"
[[ -n "$webui_volume" && -n "$models_volume" ]] || { echo 'Expected named data volumes' >&2; exit 1; }
bash "$app_dir/backup.sh"
"${compose[@]}" stop open-webui ollama
docker run --rm -v "$webui_volume:/webui" -v "$models_volume:/models" -v "$staging:/backup:ro" alpine:3.22 \
  sh -c 'find /webui -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && find /models -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /webui -xzf /backup/webui.tar.gz && tar -C /models -xzf /backup/models.tar.gz'
"${compose[@]}" up -d --wait --wait-timeout 600
echo "Restored: $archive"
echo 'Archived configuration.env was not activated. Preserve its OPEN_WEBUI_SECRET and use matching app/Ollama versions. Compare it with active .env before restoring.'
