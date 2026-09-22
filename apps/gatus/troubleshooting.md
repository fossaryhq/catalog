### Gatus exits immediately

Gatus rejects an invalid configuration instead of starting with part of it:

```bash
docker compose ps --all
docker compose logs --tail=200 gatus
```

YAML indentation, a duplicate primitive setting split across files, and an
invalid condition are common causes. Fix `config/config.yaml`, then run `docker
compose up -d` again.

### `/health` works but no check is green

`/health` only proves that Gatus serves requests. Inspect the endpoint result and
container logs:

```bash
read -r -p 'Username: ' GATUS_USERNAME
read -r -s -p 'Password: ' GATUS_PASSWORD
curl --user "${GATUS_USERNAME}:${GATUS_PASSWORD}" \
  http://127.0.0.1:8080/api/v1/endpoints/statuses
docker compose logs --tail=200 gatus
```

Run the same DNS lookup or HTTP request from the server. A target that works in
your browser may be blocked from the server, resolve to a private address, or
present a different certificate there.

### Port 8080 is taken

Change `GATUS_PORT` in `.env`, then recreate the container:

```bash
docker compose up -d
```

Update the reverse proxy's upstream port too. Leave the bind on `127.0.0.1`.

### The dashboard returns 401

Use the current `GATUS_USERNAME` from `.env` and the plain password whose hash is
stored in `GATUS_PASSWORD_BCRYPT_BASE64`. If you changed them, recreate rather
than merely restarting the process:

```bash
docker compose up -d --force-recreate
```

Do not remove the `security` block to regain access on a public server. Set new
credentials and verify them through the localhost address first.

### History disappears after a restart

Confirm that Gatus uses SQLite at `/data/data.db` and that the expected volume is
mounted:

```bash
docker compose config
docker volume inspect gatus-data
```

If `storage.type` became `memory`, new results were never persisted. Restore the
configuration and database from backup before deleting any old volume.
