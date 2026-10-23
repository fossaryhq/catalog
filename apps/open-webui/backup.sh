#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$app_dir"
env_file="${FOSSARY_ENV_FILE:-$app_dir/.env}"
[[ -f "$env_file" ]] || { echo "Missing $env_file" >&2; exit 2; }
set -a
# shellcheck disable=SC1091
. "$env_file"
set +a
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-open-webui}" --env-file "$env_file" --file "$app_dir/compose.yaml")
backup_dir="${OPEN_WEBUI_BACKUP_DIR:-$app_dir/backups}"
mkdir -p "$backup_dir"
backup_dir="$(cd "$backup_dir" && pwd)"
staging="$(mktemp -d)"
restart_containers=()
cleanup() {
  status=$?
  trap - EXIT INT TERM
  for container in "${restart_containers[@]}"; do docker start "$container" >/dev/null || true; done
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
webui_id="$("${compose[@]}" ps --all --quiet open-webui)"
ollama_id="$("${compose[@]}" ps --all --quiet ollama)"
[[ -n "$webui_id" && -n "$ollama_id" ]] || { echo 'Start the recipe before backup' >&2; exit 1; }
webui_volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/backend/data"}}{{.Name}}{{end}}{{end}}' "$webui_id")"
models_volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/home/ollama/.ollama"}}{{.Name}}{{end}}{{end}}' "$ollama_id")"
[[ -n "$webui_volume" && -n "$models_volume" ]] || { echo 'Expected named data volumes' >&2; exit 1; }
# Preserve each container's prior state, and stop every writer before copying SQLite and models.
for container in "$ollama_id" "$webui_id"; do
  if [[ "$(docker inspect --format '{{.State.Running}}' "$container")" == true ]]; then restart_containers+=("$container"); fi
done
"${compose[@]}" stop open-webui ollama
docker run --rm -v "$webui_volume:/webui:ro" -v "$models_volume:/models:ro" -v "$staging:/backup" alpine:3.22 \
  sh -c 'tar -C /webui -czf /backup/webui.tar.gz . && tar -C /models -czf /backup/models.tar.gz .'
cp -- "$env_file" "$staging/configuration.env"
cp -- "$app_dir/compose.yaml" "$staging/compose.yaml"
archive="$backup_dir/open-webui-$(date -u +%Y%m%dT%H%M%S.%NZ).tar"
tar -C "$staging" -cf "$archive" webui.tar.gz models.tar.gz configuration.env compose.yaml
echo "Backup created: $archive"
echo 'The archive contains conversations, files, model weights, credentials, and encryption/session secrets. Encrypt it and copy it off-server.'
