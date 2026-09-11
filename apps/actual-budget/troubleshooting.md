### The container never becomes healthy

```bash
docker compose ps
docker compose logs --tail=200 actual
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q actual)"
```

The health check runs `node scripts/health-check.js` inside the container, which
calls `/health`. A container that starts and then fails the check almost always
has a permission problem on the volume or a `ACTUAL_LOGIN_METHOD` value that is
not one of `password`, `openid`, or `header`.

### The bootstrap screen asks for a password again

`/account/needs-bootstrap` reports whether a password has been set:

```bash
curl --fail http://127.0.0.1:5006/account/needs-bootstrap
```

`"bootstrapped":false` on an instance you already configured means the server is
looking at an empty `server-files` — usually a renamed or recreated volume.
Check `ACTUAL_DATA_VOLUME` and `docker volume ls` before setting a new password:
the old volume still holds the budget.

### The server password is lost

The image ships a reset script. It reads the password from a terminal, so run it
without `-T`:

```bash
docker compose exec actual node /app/scripts/reset-password.js
```

It asks for the new password twice and answers `Password changed!`. Budget files,
the user record, and the OpenID configuration are left alone; every browser and
desktop client that was signed in has to sign in again. Deleting
`account.sqlite` from `server-files` also forces a new bootstrap, but it throws
away the same records the script keeps — treat it as the last resort, after a
backup. If the budget itself is end-to-end encrypted, its own encryption
password is separate and neither route recovers it.

### A client refuses to sync or reports a conflict

Each client holds a complete local copy, so a server that was restored from a
backup is behind the clients. Open the budget in the client, use "Reset sync" in
the file settings, or remove the local file and download the budget from the
server again. Do this on one device at a time to avoid two clients re-uploading
divergent copies.

### Sync fails on a large budget

The upload limits are explicit: `ACTUAL_UPLOAD_FILE_SYNC_SIZE_LIMIT_MB`,
`ACTUAL_UPLOAD_SYNC_ENCRYPTED_FILE_SYNC_SIZE_LIMIT_MB`, and
`ACTUAL_UPLOAD_FILE_SIZE_LIMIT_MB`. Raise them together with the proxy's body
limit — in the Nginx sample that is `client_max_body_size` — and recreate the
container.

### Bank synchronisation does nothing

GoCardless and SimpleFIN are configured inside the application, not in this
recipe, and both need outbound HTTPS from the container. Check the log for the
provider's error, then verify egress:

```bash
docker compose exec actual node -e "fetch('https://bankaccountdata.gocardless.com/api/v2/').then(r=>console.log(r.status)).catch(e=>{console.error(e.message);process.exit(1)})"
```

### The reverse proxy returns 502 or the page loads without syncing

On the host, run `curl -I http://127.0.0.1:5006/`. If that answers, the proxy is
the problem: inside a proxy container `127.0.0.1` is the proxy itself, so use a
host gateway address or a shared Docker network. A page that loads but never
syncs usually means the proxy drops WebSocket upgrades — both sample configs
forward them.
