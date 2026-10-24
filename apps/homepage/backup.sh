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
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-homepage}" --env-file "$env_file" --file "$app_dir/compose.yaml")
backup_dir="${HOMEPAGE_BACKUP_DIR:-$app_dir/backups}"
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
container="$("${compose[@]}" ps --all --quiet homepage)"
[[ -n "$container" ]] || { echo 'Start the recipe before backup' >&2; exit 1; }
volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/config"}}{{.Source}}{{end}}{{end}}' "$container")"
[[ -n "$volume" ]] || { echo 'Expected a config bind mount' >&2; exit 1; }
if [[ "$(docker inspect --format '{{.State.Running}}' "$container")" == true ]]; then restart_containers+=("$container"); fi
"${compose[@]}" stop homepage
docker run --rm -v "$volume:/data:ro" -v "$staging:/backup" alpine:3.22 tar -C /data -czf /backup/data.tar.gz .
cp -- "$env_file" "$staging/configuration.env"
cp -- "$app_dir/compose.yaml" "$staging/compose.yaml"
archive="$backup_dir/homepage-$(date -u +%Y%m%dT%H%M%S.%NZ).tar"
tar -C "$staging" -cf "$archive" data.tar.gz configuration.env compose.yaml
echo "Backup created: $archive"
echo 'The archive contains dashboard configuration, widget credentials, login password and session secret. Encrypt it and copy it off-server.'
