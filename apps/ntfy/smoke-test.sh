#!/usr/bin/env bash
set -Eeuo pipefail
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="smoke-ntfy-${GITHUB_RUN_ID:-local}-$$"
staging="$(mktemp -d)"
export FOSSARY_ENV_FILE="$staging/.env"
umask 077
python3 - "$staging" <<'SETUP'
import secrets,sys
from pathlib import Path
p=Path(sys.argv[1]);(p/'admin-password').write_text(secrets.token_hex(24));(p/'publisher-password').write_text(secrets.token_hex(24))
SETUP
hash="$(python3 - "$staging/admin-password" <<'HASH'
import subprocess,sys
from pathlib import Path
password=Path(sys.argv[1]).read_text()
r=subprocess.run(['docker','run','--rm','-i','binwiederhier/ntfy:v2.34.0','user','hash'],input=password+'\n'+password+'\n',text=True,capture_output=True,check=True)
h=r.stdout.strip();assert h.startswith('$2') and len(h)==60
print(h)
HASH
)"
python3 - "$app_dir/.env.example" "$FOSSARY_ENV_FILE" "$project" "$staging" "$hash" <<'ENV'
from pathlib import Path
import sys
source,target,project,staging,hash=sys.argv[1:]
s=Path(source).read_text().replace('NTFY_AUTH_USERS=replace-with-a-private-bcrypt-administrator-entry',"NTFY_AUTH_USERS='ntfyadmin:"+hash+":admin'")
s+='\n'+f'COMPOSE_PROJECT_NAME={project}\nNTFY_PORT=0\nNTFY_DATA_VOLUME={project}-data\nNTFY_BACKUP_DIR={staging}/backups\n'
Path(target).write_text(s)
ENV
set -a
. "$FOSSARY_ENV_FILE"
set +a
compose=(docker compose --project-name "$project" --env-file "$FOSSARY_ENV_FILE" --file "$app_dir/compose.yaml")
cleanup() {
  status=$?
  trap - EXIT INT TERM
  "${compose[@]}" logs --no-color --tail=80 || true
  "${compose[@]}" down --volumes --remove-orphans --timeout 30 || true
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
cat > "$staging/api.py" <<'API'
import base64,json,sys,urllib.request,urllib.error
from pathlib import Path
base,action,staging=sys.argv[1:];root=Path(staging)
state=json.loads((root/'state.json').read_text()) if action!='seed' else {}
admin='Basic '+base64.b64encode(('ntfyadmin:'+ (root/'admin-password').read_text()).encode()).decode()
publisher='Basic '+base64.b64encode(('publisher:'+(root/'publisher-password').read_text()).encode()).decode()
def api(path,method='GET',body=None,auth=admin,expected=200,raw=False,headers=None):
    h={**({'Authorization':auth} if auth else {}),**(headers or {})}
    data=body if isinstance(body,bytes) else json.dumps(body).encode() if body is not None else None
    request=urllib.request.Request(base+path,data=data,method=method,headers=h)
    try:response=urllib.request.urlopen(request,timeout=15)
    except urllib.error.HTTPError as error:
        allowed=expected if isinstance(expected,tuple) else (expected,)
        assert error.code in allowed,(path,error.code,error.read())
        return None
    assert response.status==expected,(path,response.status)
    content=response.read()
    return content if raw else json.loads(content) if content else None
def messages(auth=admin):
    return [json.loads(line) for line in api('/backups/json?poll=1&since=all',raw=True,auth=auth).splitlines()]
assert api('/v1/health',auth=None)['healthy'] is True
api('/backups/json?poll=1',auth=None,expected=(401,403))
api('/backups','POST',b'anonymous publish must fail',auth=None,expected=(401,403))
if action=='empty':
    assert not messages()
    api('/v1/account/login','POST',auth=publisher,expected=(401,403))
    api(state['file_path'],auth=None,expected=404)
    print('Fresh volume has no old messages, publisher account or attachment');sys.exit(0)
assert api('/v1/account')['role']=='admin'
assert api('/v1/account',auth=publisher)['role']=='user'
if action=='seed':
    api('/v1/account','POST',{'username':'stranger','password':'not-a-real-password'},auth=None,expected=(400,401,403))
    api('/v1/account/settings','PATCH',{'language':'en','notification':{'min_priority':2}})
    api('/v1/account/subscription','POST',{'base_url':base,'topic':'backups'})
    # A live subscriber receives a newly published message through the original server.
    request=urllib.request.Request(base+'/backups/json',headers={'Authorization':publisher})
    with urllib.request.urlopen(request,timeout=15) as stream:
        assert json.loads(stream.readline())['event']=='open'
        sent=api('/backups','POST',b'Backup recovery check passed.',auth=publisher,headers={'Title':'Home server backup','Tags':'white_check_mark,backup','Priority':'4'})
        received=json.loads(stream.readline());assert received['id']==sent['id'] and received['message']==sent['message']
    file=api('/backups?filename=recovery-checklist.txt','PUT',b'Fossary ntfy recovery check\n',headers={'Content-Type':'application/octet-stream'})
    api('/v1/account/token','POST',{'label':'Backup automation','expires':0},auth=publisher)
    token=next(t['token'] for t in api('/v1/account',auth=publisher)['tokens'] if t['label']=='Backup automation')
    state={'message':sent['id'],'file':file['id'],'file_path':urllib.parse.urlsplit(file['attachment']['url']).path,'token':token}
    (root/'state.json').write_text(json.dumps(state))
assert state['message'] in [m['id'] for m in messages(publisher)]
assert state['file'] in [m['id'] for m in messages()]
# ntfy attachment URLs are bearer links, not protected by topic ACLs.
assert api(state['file_path'],auth=None,raw=True)==b'Fossary ntfy recovery check\n'
assert api('/v1/account')['notification']['min_priority']==2
assert any(s['topic']=='backups' for s in api('/v1/account')['subscriptions'])
assert api('/backups','POST',b'Token and ACL recovery check.',auth='Bearer '+state['token'])['event']=='message'
api('/other-topic','POST',b'Out-of-scope token must fail',auth='Bearer '+state['token'],expected=403)
api('/other-topic/json?poll=1',auth=publisher,expected=403)
print('ntfy '+action+' passed: messages, attachment bytes, credentials, token, ACL and account settings')
API
"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up -d --wait --wait-timeout 180
publisher_password="$(cat "$staging/publisher-password")"
"${compose[@]}" exec -T -e NTFY_PASSWORD="$publisher_password" ntfy ntfy user add publisher
"${compose[@]}" exec -T ntfy ntfy access publisher backups rw
published="$("${compose[@]}" port ntfy 8080)"
[[ "$published" == 127.0.0.1:* ]]
python3 "$staging/api.py" "http://$published" seed "$staging"
bash "$app_dir/backup.sh"
archives=("$NTFY_BACKUP_DIR"/ntfy-*.tar)
[[ "$(stat -c %a "${archives[0]}")" == 600 ]]
"${compose[@]}" up -d --wait --wait-timeout 180
tar -cf "$staging/incomplete.tar" --files-from /dev/null
if bash "$app_dir/restore.sh" "$staging/incomplete.tar"; then echo 'Incomplete archive accepted' >&2; exit 1; fi
"${compose[@]}" down --volumes --timeout 30
"${compose[@]}" up -d --wait --wait-timeout 180
published="$("${compose[@]}" port ntfy 8080)"
python3 "$staging/api.py" "http://$published" empty "$staging"
bash "$app_dir/restore.sh" "${archives[0]}"
published="$("${compose[@]}" port ntfy 8080)"
python3 "$staging/api.py" "http://$published" verify "$staging"
"${compose[@]}" stop ntfy
bash "$app_dir/backup.sh"
container="$("${compose[@]}" ps --all --quiet ntfy)"
[[ "$(docker inspect --format '{{.State.Running}}' "$container")" == false ]]
echo 'ntfy live delivery, messages, bearer attachment, tokens, ACLs, backup and restore passed'
