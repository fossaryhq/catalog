#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

backup_dir="${PIHOLE_BACKUP_DIR:-$script_dir/backups}"
timestamp="$(date -u +%Y%m%dT%H%M%S.%NZ)"
mkdir -p "$backup_dir"

# Resolve the volume actually mounted by Compose. Docker Compose reads .env,
# whereas this shell does not; PIHOLE_VOLUME may therefore differ from its
# shell default even when the operator has configured it correctly in .env.
container_id="$(docker compose ps --all --quiet pi-hole)"
if [[ -z "$container_id" ]]; then
  echo "Pi-hole container not found; start the recipe before backing it up" >&2
  exit 1
fi
volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/etc/pihole"}}{{.Name}}{{end}}{{end}}' "$container_id")"
if [[ -z "$volume" ]]; then
  echo "The Pi-hole container has no named /etc/pihole volume" >&2
  exit 1
fi

# Quiesce the SQLite databases before copying the whole configuration volume.
docker compose stop pi-hole
restart_container() { docker compose start pi-hole >/dev/null; }
trap restart_container EXIT

docker run --rm \
  -v "${volume}:/source:ro" \
  -v "${backup_dir}:/backup" \
  alpine:3.22 \
  tar -C /source -czf "/backup/pi-hole-${timestamp}.tar.gz" .

echo "Backup created: $backup_dir/pi-hole-${timestamp}.tar.gz"
