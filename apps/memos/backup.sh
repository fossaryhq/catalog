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
compose=(docker compose --project-name "${COMPOSE_PROJECT_NAME:-memos}" --env-file "$env_file" --file "$app_dir/compose.yaml")
backup_dir="${MEMOS_BACKUP_DIR:-$app_dir/backups}"
mkdir -p "$backup_dir"
backup_dir="$(cd "$backup_dir" && pwd)"
staging="$(mktemp -d)"
stopped=false
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ "$stopped" == true ]]; then "${compose[@]}" start memos >/dev/null || true; fi
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
container_id="$("${compose[@]}" ps --all --quiet memos)"
[[ -n "$container_id" ]] || { echo "Start the Memos recipe before backup" >&2; exit 1; }
volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/var/opt/memos"}}{{.Name}}{{end}}{{end}}' "$container_id")"
[[ -n "$volume" ]] || { echo "No named /var/opt/memos volume found" >&2; exit 1; }

# Stop writers so the database dump and uploaded files describe one state.
was_running="$(docker inspect --format '{{.State.Running}}' "$container_id")"
"${compose[@]}" stop memos
stopped="$was_running"
docker run --rm -v "$volume:/source:ro" -v "$staging:/backup" alpine:3.22 tar -C /source -czf /backup/data.tar.gz .
cp -- "$env_file" "$staging/configuration.env"
tar -C "$app_dir" -czf "$staging/config.tar.gz" config
cp -- "$app_dir/compose.yaml" "$staging/compose.yaml"
archive="$backup_dir/memos-$(date -u +%Y%m%dT%H%M%S.%NZ).tar"
tar -C "$staging" -cf "$archive" data.tar.gz config.tar.gz configuration.env compose.yaml
echo "Backup created: $archive"
echo "The archive contains the service secret, accounts, private notes, and uploaded files. Encrypt it and copy it off-server."
