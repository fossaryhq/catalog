#!/usr/bin/env bash
set -Eeuo pipefail
app_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="smoke-open-webui-${GITHUB_RUN_ID:-local}-$$"
staging="$(mktemp -d)"
export FOSSARY_ENV_FILE="$staging/.env"
python3 - "$app_dir/.env.example" "$FOSSARY_ENV_FILE" "$project" "$staging" <<'PY'
from pathlib import Path
import secrets,sys
source,target,project,staging=sys.argv[1:]
s=Path(source).read_text().replace('replace-with-output-of-openssl-rand-hex-32',secrets.token_hex(32)).replace('replace-with-a-different-strong-random-password',secrets.token_hex(24))
s+='\n'+f'COMPOSE_PROJECT_NAME={project}\nOPEN_WEBUI_PORT=0\nOPEN_WEBUI_DATA_VOLUME={project}-data\nOLLAMA_DATA_VOLUME={project}-models\nOPEN_WEBUI_BACKUP_DIR={staging}/backups\n'
Path(target).write_text(s);Path(target).chmod(0o600)
PY
set -a
. "$FOSSARY_ENV_FILE"
set +a
compose=(docker compose --project-name "$project" --env-file "$FOSSARY_ENV_FILE" --file "$app_dir/compose.yaml")
cleanup() {
  status=$?
  trap - EXIT INT TERM
  "${compose[@]}" logs --no-color --tail=100 || true
  "${compose[@]}" down --volumes --remove-orphans --timeout 60 || true
  rm -rf "$staging"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
trap 'echo "Check failed on line $LINENO: $BASH_COMMAND" >&2' ERR
cat > "$staging/api.py" <<'PY'
import json,sys,urllib.request,urllib.error,uuid
from pathlib import Path
base,action,statefile,envfile=sys.argv[1:]
env=dict(line.split('=',1) for line in Path(envfile).read_text().splitlines() if '=' in line and not line.startswith('#'))
state=json.load(open(statefile)) if action!='seed' else {}
token=None
model='qwen3:0.6b'
def api(path,method='GET',body=None,auth=True,expected=200,raw=False,headers=None):
    h={'Content-Type':'application/json',**(headers or {})}
    if token and auth:h['Authorization']='Bearer '+token
    data=body if isinstance(body,bytes) else json.dumps(body).encode() if body is not None else None
    request=urllib.request.Request(base+path,method=method,headers=h,data=data)
    try:response=urllib.request.urlopen(request,timeout=240)
    except urllib.error.HTTPError as error:
        allowed=expected if isinstance(expected,tuple) else (expected,)
        assert error.code in allowed,(path,error.code,error.read())
        return None
    assert response.status==expected,(path,response.status)
    content=response.read()
    return content if raw else json.loads(content) if content else None
login=api('/api/v1/auths/signin','POST',{'email':env['OPEN_WEBUI_ADMIN_EMAIL'],'password':env['OPEN_WEBUI_ADMIN_PASSWORD']})
assert login['role']=='admin'
token=login['token']
assert api('/health/db')['status'] is True
if action=='empty':
    assert model not in [m['id'] for m in api('/api/models')['data']]
    assert state['chat'] not in [c['id'] for c in api('/api/v1/chats/list')]
    api('/api/v1/chats/'+state['chat'],expected=(401,404))
    print('Fresh volumes contain neither the saved chat nor the model')
    sys.exit(0)
if action=='seed':
    api('/api/v1/auths/signup','POST',{'name':'Stranger','email':'stranger@example.com','password':uuid.uuid4().hex},auth=False,expected=403)
if action in ('seed','verify'):
    assert model in [m['id'] for m in api('/api/models')['data']]
    tags=api('/ollama/api/tags')['models']
    digest=next(m['digest'] for m in tags if m['name']==model)
    reply=api('/api/chat/completions','POST',{'model':model,'messages':[{'role':'user','content':'Say hello in one short sentence. /no_think'}],'stream':False,'params':{'think':False,'temperature':0,'num_predict':120}})
    content=reply['choices'][0]['message']['content']
    assert content.strip() and reply['choices'][0]['finish_reason']=='stop'
if action=='seed':
    user_id,assistant_id=str(uuid.uuid4()),str(uuid.uuid4())
    messages=[{'id':user_id,'role':'user','content':'Say hello in one short sentence.','parentId':None,'childrenIds':[assistant_id]}, {'id':assistant_id,'role':'assistant','content':content,'model':model,'parentId':user_id,'childrenIds':[],'done':True}]
    chat=api('/api/v1/chats/new','POST',{'chat':{'title':'Local inference recovery check','models':[model],'messages':messages,'history':{'messages':{m['id']:m for m in messages},'currentId':assistant_id}}})
    boundary='fossary-'+uuid.uuid4().hex
    file_bytes=b'Fossary Open WebUI recovery check\n'
    payload=(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="recovery-checklist.txt"\r\nContent-Type: text/plain\r\n\r\n').encode()+file_bytes+f'\r\n--{boundary}--\r\n'.encode()
    file=api('/api/v1/files/?process=false','POST',payload,headers={'Content-Type':'multipart/form-data; boundary='+boundary})
    state={'chat':chat['id'],'file':file['id'],'answer':content,'digest':digest}
    Path(statefile).write_text(json.dumps(state))
if action in ('seed','verify'):
    assert digest==state['digest']
    chat=api('/api/v1/chats/'+state['chat'])
    assert chat['chat']['messages'][-1]['content']==state['answer']
    assert api('/api/v1/files/'+state['file']+'/content',raw=True)==b'Fossary Open WebUI recovery check\n'
    api('/api/v1/chats/'+state['chat'],auth=False,expected=(401,403))
    api('/api/v1/files/'+state['file']+'/content',auth=False,expected=(401,403))
if action=='delete':
    api('/api/v1/chats/'+state['chat'],'DELETE')
    api('/api/v1/files/'+state['file'],'DELETE')
    assert state['chat'] not in [c['id'] for c in api('/api/v1/chats/list')]
    api('/api/v1/chats/'+state['chat'],expected=(401,404))
print('Open WebUI API '+action+' passed')
PY
"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up -d --wait --wait-timeout 600
"${compose[@]}" exec -T ollama ollama pull qwen3:0.6b > "$staging/model-pull.log" 2>&1 || { tail -c 2000 "$staging/model-pull.log"; exit 1; }
published="$("${compose[@]}" port open-webui 8080)"
[[ "$published" == 127.0.0.1:* ]]
python3 "$staging/api.py" "http://$published" seed "$staging/state.json" "$FOSSARY_ENV_FILE"
bash "$app_dir/backup.sh"
archives=("$OPEN_WEBUI_BACKUP_DIR"/open-webui-*.tar)
[[ "$(stat -c %a "${archives[0]}")" == 600 ]]
"${compose[@]}" up -d --wait --wait-timeout 600
published="$("${compose[@]}" port open-webui 8080)"
tar -cf "$staging/incomplete.tar" --files-from /dev/null
if bash "$app_dir/restore.sh" "$staging/incomplete.tar"; then echo 'Incomplete archive accepted' >&2; exit 1; fi
python3 "$staging/api.py" "http://$published" delete "$staging/state.json" "$FOSSARY_ENV_FILE"
"${compose[@]}" down --volumes --timeout 60
"${compose[@]}" up -d --wait --wait-timeout 600
published="$("${compose[@]}" port open-webui 8080)"
python3 "$staging/api.py" "http://$published" empty "$staging/state.json" "$FOSSARY_ENV_FILE"
bash "$app_dir/restore.sh" "${archives[0]}"
published="$("${compose[@]}" port open-webui 8080)"
python3 "$staging/api.py" "http://$published" verify "$staging/state.json" "$FOSSARY_ENV_FILE"
"${compose[@]}" stop open-webui ollama
bash "$app_dir/backup.sh"
for service in open-webui ollama; do
  container="$("${compose[@]}" ps --all --quiet "$service")"
  [[ "$(docker inspect --format '{{.State.Running}}' "$container")" == false ]]
done
echo 'Open WebUI CPU inference, chats, file, privacy, model weights, backup and restore passed'
