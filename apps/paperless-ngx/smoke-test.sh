#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${COMPOSE_PROJECT_NAME:-smoke-paperless-ngx-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$}"
status_file="$(mktemp)"
# backup.sh and restore.sh read their own .env and run `docker compose` beside
# it, so they are exercised from a copy of the recipe rather than from the
# catalog directory, which has no .env.
work_dir="$(mktemp -d)"
backup_dir="$(mktemp -d)"

export PAPERLESS_PORT=0
export PAPERLESS_URL=http://localhost:8000
export PAPERLESS_SECRET_KEY="smoke-secret-${project}"
export PAPERLESS_DB_PASSWORD="smoke-db-${project}"
export PAPERLESS_DATA_VOLUME="${project}-data"
export PAPERLESS_MEDIA_VOLUME="${project}-media"
export PAPERLESS_EXPORT_VOLUME="${project}-export"
export PAPERLESS_CONSUME_VOLUME="${project}-consume"
export PAPERLESS_DB_VOLUME="${project}-database"
export PAPERLESS_BROKER_VOLUME="${project}-broker"
export COMPOSE_PROJECT_NAME="$project"

compose=(docker compose --project-name "$project" --env-file "$app_dir/.env.example" --file "$app_dir/compose.yaml")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  set +e
  "${compose[@]}" ps --all
  "${compose[@]}" logs --no-color --timestamps --tail=300
  "${compose[@]}" down --volumes --remove-orphans --timeout 60
  rm -f "$status_file"
  rm -rf "$work_dir" "$backup_dir"
  exit "$status"
}
# Every failed check names itself: `grep --quiet` and `test` say nothing, and all
# the CI log would keep of them is an exit code.
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
trap cleanup EXIT
trap 'exit 130' INT TERM

# Django prints its own startup lines before the answer, so every query marks
# the value it is asked for and the check reads that line alone.
query() {
  "${compose[@]}" exec -T webserver python3 manage.py shell -c "$1" | tr -d '\r' | grep '^SMOKE '
}

"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up --detach --wait --wait-timeout "${SMOKE_WAIT_TIMEOUT:-600}"
published="$("${compose[@]}" port webserver 8000)"
case "$published" in
  127.0.0.1:[0-9]*) ;;
  *) echo "Unexpected published address: $published" >&2; exit 1 ;;
esac
curl --silent --show-error --output /dev/null --write-out '%{http_code}' "http://${published}/" > "$status_file"
grep --extended-regexp --quiet '^30[1278]$' "$status_file"

# Verify that backup and restore return a document, not only container health: a
# document is a row in PostgreSQL, a file in the media volume, and an entry in
# the search index at once, so one check covers every half of the archive.
# Ghostscript ships in the image, so the page is produced where it is consumed
# and the test needs nothing on the host. Inline PostScript through `gs -c`
# renders an empty page; a file does not.
"${compose[@]}" exec -T webserver /bin/bash -c 'set -e
cat > /tmp/fossary-smoke.ps <<"POSTSCRIPT"
%!PS
/Helvetica findfont 24 scalefont setfont
72 740 moveto (Fossary smoke test document) show
/Helvetica findfont 14 scalefont setfont
72 700 moveto (This page proves the backup and restore round trip.) show
showpage
POSTSCRIPT
gs -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -sPAPERSIZE=a4 -dFIXEDMEDIA \
  -o /tmp/fossary-smoke.pdf /tmp/fossary-smoke.ps
# The consumer watches for a complete file, so the page is moved in rather than
# written in place.
mv /tmp/fossary-smoke.pdf "/usr/src/paperless/consume/fossary-smoke.pdf"'

consumed=""
for _ in $(seq 1 "${SMOKE_CONSUME_ATTEMPTS:-40}"); do
  if query 'from documents.models import Document
print("SMOKE", Document.objects.filter(title="fossary-smoke").count())' | grep --fixed-strings --line-regexp --quiet "SMOKE 1"; then
    consumed=yes
    break
  fi
  sleep 10
done
test -n "$consumed"
# OCR has to have produced the text of the page, not just a document row.
query 'from documents.models import Document
print("SMOKE", "text" if "backup and restore round trip" in Document.objects.get(title="fossary-smoke").content else "no text")' \
  | grep --fixed-strings --line-regexp --quiet "SMOKE text"

cp -- "$app_dir/compose.yaml" "$app_dir/backup.sh" "$app_dir/restore.sh" "$work_dir/"
{
  printf 'PAPERLESS_PORT=%s\n' "$PAPERLESS_PORT"
  printf 'PAPERLESS_URL=%s\n' "$PAPERLESS_URL"
  printf 'PAPERLESS_SECRET_KEY=%s\n' "$PAPERLESS_SECRET_KEY"
  printf 'PAPERLESS_DB_PASSWORD=%s\n' "$PAPERLESS_DB_PASSWORD"
  printf 'PAPERLESS_DATA_VOLUME=%s\n' "$PAPERLESS_DATA_VOLUME"
  printf 'PAPERLESS_MEDIA_VOLUME=%s\n' "$PAPERLESS_MEDIA_VOLUME"
  printf 'PAPERLESS_EXPORT_VOLUME=%s\n' "$PAPERLESS_EXPORT_VOLUME"
  printf 'PAPERLESS_CONSUME_VOLUME=%s\n' "$PAPERLESS_CONSUME_VOLUME"
  printf 'PAPERLESS_DB_VOLUME=%s\n' "$PAPERLESS_DB_VOLUME"
  printf 'PAPERLESS_BROKER_VOLUME=%s\n' "$PAPERLESS_BROKER_VOLUME"
  printf 'PAPERLESS_BACKUP_DIR=%s\n' "$backup_dir"
} > "$work_dir/.env"

bash "$work_dir/backup.sh"
archives=("$backup_dir"/paperless-ngx-*.tar)
test -f "${archives[0]}"
# The archive carries .env and every document, so it must not be readable by
# anyone else on the server.
test "$(stat -c %a "${archives[0]}")" = 600

query 'from documents.models import Document
Document.objects.filter(title="fossary-smoke").delete()
print("SMOKE", Document.objects.filter(title="fossary-smoke").count())' \
  | grep --fixed-strings --line-regexp --quiet "SMOKE 0"

bash "$work_dir/restore.sh" "${archives[0]}"
"${compose[@]}" up --detach --wait --wait-timeout "${SMOKE_WAIT_TIMEOUT:-600}"
# The document has to come back with its text, not only as a row.
query 'from documents.models import Document
document = Document.objects.filter(title="fossary-smoke").first()
print("SMOKE", "restored" if document and "backup and restore round trip" in document.content else "missing")' \
  | grep --fixed-strings --line-regexp --quiet "SMOKE restored"
# The importer copies files as well as rows; the sanity checker is what notices
# a document whose file, archive rendition, or checksum did not come back.
"${compose[@]}" exec -T webserver document_sanity_checker

echo "Paperless-ngx smoke test passed on $published"
