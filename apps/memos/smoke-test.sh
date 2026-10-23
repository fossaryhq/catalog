#!/usr/bin/env bash
set -Eeuo pipefail
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="smoke-memos-${GITHUB_RUN_ID:-local}-$$"
staging="$(mktemp -d)"
export COMPOSE_PROJECT_NAME="$project"
export MEMOS_DATA_VOLUME="$project-data"
export MEMOS_PORT=0
export MEMOS_BACKUP_DIR="$staging/backups"
export FOSSARY_ENV_FILE="$staging/.env"
cp "$app_dir/.env.example" "$FOSSARY_ENV_FILE"
compose=(docker compose --project-name "$project" --env-file "$FOSSARY_ENV_FILE" --file "$app_dir/compose.yaml")
cleanup() {
  status=$?
  trap - EXIT INT TERM
  "${compose[@]}" logs --no-color --tail=150 || true
  "${compose[@]}" down --volumes --remove-orphans --timeout 30 || true
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
# Scripts source this trusted environment; it must name the same isolated stack.
cat >> "$FOSSARY_ENV_FILE" <<ENV
COMPOSE_PROJECT_NAME=$project
MEMOS_PORT=0
MEMOS_DATA_VOLUME=$MEMOS_DATA_VOLUME
MEMOS_BACKUP_DIR=$MEMOS_BACKUP_DIR
ENV
cat > "$staging/api.py" <<'PY'
import base64, json, secrets, sys, urllib.request, urllib.error
base, action, statefile = sys.argv[1:]
state = json.load(open(statefile)) if action != 'seed' else {'username': 'alex', 'password': secrets.token_hex(24)}
token = None
def api(path, method='GET', body=None, auth=True, expected=200, raw=False):
    headers = {'Content-Type': 'application/json'}
    if token and auth: headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(base + path, method=method, headers=headers, data=json.dumps(body).encode() if body is not None else None)
    try:
        response = urllib.request.urlopen(request, timeout=30)
    except urllib.error.HTTPError as error:
        assert error.code == expected, (path, error.code, error.read())
        return None
    assert response.status == expected, (path, response.status)
    content = response.read()
    return content if raw else json.loads(content) if content else None
if action == 'seed':
    profile = api('/api/v1/instance/profile')
    assert profile['version'] == '0.31.0' and profile['needsSetup']
    assert profile['accessMode'] == 'INSTANCE_ACCESS_MODE_PRIVATE'
    user = api('/api/v1/users', 'POST', {**state, 'displayName': 'Alex Morgan'})
    assert user['role'] == 'ADMIN'
token = api('/api/v1/auth/signin', 'POST', {'passwordCredentials': {'username': state['username'], 'password': state['password']}})['accessToken']
if action == 'seed':
    api('/api/v1/users', 'POST', {'username': 'stranger', 'password': secrets.token_hex(24)}, auth=False, expected=403)
    memo = api('/api/v1/memos', 'POST', {'content': '# Recovery check\n\n- [x] Save the notes\n- [ ] Download an attachment\n\n#home/server', 'visibility': 'PRIVATE'})
    attachment = api('/api/v1/attachments', 'POST', {'filename': 'recovery-checklist.txt', 'type': 'text/plain', 'content': base64.b64encode(b'Fossary Memos recovery check\n').decode()})
    api('/api/v1/' + memo['name'] + '/attachments', 'PATCH', {'attachments': [attachment]})
    state.update(memo=memo['name'], attachment=attachment['name'], content=memo['content'])
    with open(statefile, 'w') as output: json.dump(state, output)
if action in ('seed', 'verify'):
    memo = api('/api/v1/' + state['memo'])
    assert memo['content'] == state['content'] and memo['visibility'] == 'PRIVATE'
    api('/api/v1/' + state['memo'], auth=False, expected=401)
    files = api('/api/v1/' + state['memo'] + '/attachments')['attachments']
    assert any(item['name'] == state['attachment'] for item in files)
    assert api('/file/' + state['attachment'] + '/recovery-checklist.txt', raw=True) == b'Fossary Memos recovery check\n'
    api('/file/' + state['attachment'] + '/recovery-checklist.txt', auth=False, expected=401)
if action == 'delete':
    api('/api/v1/' + state['memo'] + '?force=true', 'DELETE')
    api('/api/v1/' + state['memo'], expected=404)
print('Memos API ' + action + ' passed')
PY
"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up -d --wait --wait-timeout 300
published="$("${compose[@]}" port memos 5230)"
[[ "$published" == 127.0.0.1:* ]]
base="http://$published"
curl --fail --silent --show-error "$base/healthz" | grep -q 'Service ready.'
python3 "$staging/api.py" "$base" seed "$staging/state.json"
bash "$app_dir/backup.sh"
archives=("$MEMOS_BACKUP_DIR"/memos-*.tar)
[[ "$(stat -c %a "${archives[0]}")" == 600 ]]
"${compose[@]}" up -d --wait --wait-timeout 300
published="$("${compose[@]}" port memos 5230)"
base="http://$published"
tar -cf "$staging/incomplete.tar" --files-from /dev/null
if bash "$app_dir/restore.sh" "$staging/incomplete.tar"; then
  echo 'Incomplete backup accepted' >&2
  exit 1
fi
python3 "$staging/api.py" "$base" verify "$staging/state.json"
python3 "$staging/api.py" "$base" delete "$staging/state.json"
"${compose[@]}" down --volumes --timeout 30
"${compose[@]}" up -d --wait --wait-timeout 300
published="$("${compose[@]}" port memos 5230)"
curl --fail --silent --show-error "http://$published/api/v1/instance/profile" | python3 -c 'import json,sys; assert json.load(sys.stdin)["needsSetup"]'
bash "$app_dir/restore.sh" "${archives[0]}"
published="$("${compose[@]}" port memos 5230)"
python3 "$staging/api.py" "http://$published" verify "$staging/state.json"
"${compose[@]}" stop memos
bash "$app_dir/backup.sh"
container_id="$("${compose[@]}" ps --all --quiet memos)"
[[ "$(docker inspect --format '{{.State.Running}}' "$container_id")" == false ]]
echo 'Memos login, privacy, notes, attachment, backup and restore passed'
