#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: $0 path/to/pi-hole-backup.tar.gz" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$script_dir"

# Make the current state recoverable before replacing the named volume.
bash "$script_dir/backup.sh"
container_id="$(docker compose ps --all --quiet pi-hole)"
if [[ -z "$container_id" ]]; then
  echo "Pi-hole container not found; start the recipe before restoring" >&2
  exit 1
fi
volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/etc/pihole"}}{{.Name}}{{end}}{{end}}' "$container_id")"
if [[ -z "$volume" ]]; then
  echo "The Pi-hole container has no named /etc/pihole volume" >&2
  exit 1
fi
docker compose stop pi-hole
restart_container() { docker compose start pi-hole >/dev/null; }
trap restart_container EXIT

# Accept only archives with relative paths. The backup script writes ./... .
if tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  echo "Unsafe archive paths; restore aborted" >&2
  exit 1
fi

docker run --rm \
  -v "${volume}:/target" \
  -v "${archive}:/backup.tar.gz:ro" \
  alpine:3.22 \
  sh -c 'find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /target -xzf /backup.tar.gz'

echo "Backup restored from: $archive"
