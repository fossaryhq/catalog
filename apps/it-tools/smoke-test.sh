#!/usr/bin/env bash
set -Eeuo pipefail
source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
export COMPOSE_PROJECT_NAME
COMPOSE_PROJECT_NAME="it-tools-smoke-$(date +%s)-$$"
export FOSSARY_ENV_FILE="$tmp/recipe/.env"
export IT_TOOLS_BACKUP_DIR="$tmp/backups"
export IT_TOOLS_PORT
IT_TOOLS_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
export IT_TOOLS_VERSION="${IT_TOOLS_VERSION:-2024.10.22-7ca5933}"
umask 077
mkdir "$tmp/recipe"
cp -R "$source_dir/config" "$tmp/recipe/"
chmod 644 "$tmp/recipe/config/nginx.conf"
cp "$source_dir/compose.yaml" "$source_dir/backup.sh" "$source_dir/restore.sh" "$tmp/recipe/"
printf 'IT_TOOLS_VERSION=%s\nIT_TOOLS_PORT=%s\n' "$IT_TOOLS_VERSION" "$IT_TOOLS_PORT" > "$FOSSARY_ENV_FILE"
compose=(docker compose --project-name "$COMPOSE_PROJECT_NAME" --env-file "$FOSSARY_ENV_FILE" --file "$tmp/recipe/compose.yaml")
cleanup() {
  status=$?
  trap - EXIT INT TERM
  "${compose[@]}" logs --no-color --tail=40 || true
  "${compose[@]}" down --volumes --remove-orphans || true
  rm -rf "$tmp"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
"${compose[@]}" config --quiet
"${compose[@]}" up -d --wait --wait-timeout 120
base="http://127.0.0.1:$IT_TOOLS_PORT"
curl -fsS "$base/" > "$tmp/index.html"
grep -q '<title>IT Tools' "$tmp/index.html"
curl -fsS "$base/json-to-yaml-converter" | cmp -s - "$tmp/index.html"
[[ "$("${compose[@]}" exec -T it-tools id -u)" == 101 ]]
if "${compose[@]}" exec -T it-tools touch /usr/share/nginx/html/write-probe; then echo 'Static root was writable' >&2; exit 1; fi
# Isolated test dependency; the deployed recipe has no Node or browser requirement.
npm --prefix "$tmp/browser" install --no-audit --no-fund --no-package-lock --no-save playwright@1.62.1 >/dev/null
node "$tmp/browser/node_modules/playwright/cli.js" install chromium >/dev/null
node "$source_dir/smoke-browser.mjs" "$base" "$tmp/browser/node_modules/playwright/index.mjs"
python3 - "$tmp/recipe/config/nginx.conf" <<'PYCODE'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text().replace('add_header Referrer-Policy', 'add_header X-Recipe-Recovery verified always;\n        add_header Referrer-Policy');p.write_text(s)
PYCODE
"${compose[@]}" restart it-tools
curl --retry 20 --retry-delay 1 --retry-connrefused -fsSI "$base/" | grep -qi 'X-Recipe-Recovery: verified'
bash "$tmp/recipe/backup.sh"
archive="$(find "$tmp/backups" -name 'it-tools-*.tar.gz' | sort | tail -n 1)"
[[ "$(stat -c %a "$archive")" == 600 ]]
mkdir "$tmp/invalid"
printf invalid > "$tmp/invalid/sample"
tar -C "$tmp/invalid" -czf "$tmp/invalid.tar.gz" sample
if bash "$tmp/recipe/restore.sh" "$tmp/invalid.tar.gz"; then echo 'Incomplete archive accepted' >&2; exit 1; fi
curl -fsSI "$base/" | grep -qi 'X-Recipe-Recovery: verified'
mkdir "$tmp/invalid/config"
printf 'invalid nginx directive;\n' > "$tmp/invalid/config/nginx.conf"
cp "$FOSSARY_ENV_FILE" "$tmp/invalid/configuration.env"
cp "$tmp/recipe/compose.yaml" "$tmp/invalid/compose.yaml"
tar -C "$tmp/invalid" -czf "$tmp/invalid-nginx.tar.gz" config configuration.env compose.yaml
if bash "$tmp/recipe/restore.sh" "$tmp/invalid-nginx.tar.gz"; then echo 'Invalid Nginx accepted' >&2; exit 1; fi
curl -fsSI "$base/" | grep -qi 'X-Recipe-Recovery: verified'
"${compose[@]}" down --volumes
rm "$tmp/recipe/config/nginx.conf"
cp "$source_dir/config/nginx.conf" "$tmp/recipe/config/nginx.conf"
chmod 644 "$tmp/recipe/config/nginx.conf"
"${compose[@]}" up -d --wait --wait-timeout 120
if curl -fsSI "$base/" | grep -qi 'X-Recipe-Recovery: verified'; then echo 'Fresh configuration unexpectedly retained old marker' >&2; exit 1; fi
bash "$tmp/recipe/restore.sh" "$archive"
curl -fsSI "$base/" | grep -qi 'X-Recipe-Recovery: verified'
node "$source_dir/smoke-browser.mjs" "$base" "$tmp/browser/node_modules/playwright/index.mjs"
"${compose[@]}" stop it-tools
bash "$tmp/recipe/backup.sh"
[[ -z "$("${compose[@]}" ps --status running --quiet it-tools)" ]]
echo 'IT Tools smoke and fresh-configuration recovery passed; browser storage is not in server backups.'
