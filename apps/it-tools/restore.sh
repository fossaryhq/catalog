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
[[ $# -eq 1 && -f "$1" ]] || { echo "Usage: $0 path/to/it-tools-backup.tar.gz" >&2; exit 2; }
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
gzip -t "$archive"
tar -tzf "$archive" > "$staging/files"
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$staging/files"; then echo 'Unsafe archive paths' >&2; exit 1; fi
tar -C "$staging" -xzf "$archive" config/nginx.conf configuration.env compose.yaml
for file in config/nginx.conf configuration.env compose.yaml; do
  [[ -f "$staging/$file" && -s "$staging/$file" && ! -L "$staging/$file" ]] || { echo "Missing $file" >&2; exit 1; }
done
chmod 755 "$staging" "$staging/config"
chmod 644 "$staging/config/nginx.conf"
docker run --rm --user 101:101 --cap-drop ALL --read-only --tmpfs /tmp:rw,noexec,nosuid,size=32m,mode=1777 \
  -v "$staging/config/nginx.conf:/etc/fossary/nginx.conf:ro" --entrypoint nginx \
  "ghcr.io/corentinth/it-tools:${IT_TOOLS_VERSION:-2024.10.22-7ca5933}" -t -c /etc/fossary/nginx.conf
bash "$app_dir/backup.sh"
"${compose[@]}" stop it-tools
cp "$staging/config/nginx.conf" config/nginx.conf
chmod 644 config/nginx.conf
"${compose[@]}" up -d --wait --wait-timeout 120
echo 'Configuration restored. Saved environment/Compose were not activated; compare them privately and use the matching image version. Browser storage is unchanged.'
