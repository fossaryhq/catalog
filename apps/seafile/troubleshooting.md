### The first start fails with "is not a valid ip or domain"

The setup script validates `SEAFILE_SERVER_HOSTNAME` and rejects `localhost` and
anything without a dot. Set a real host name — the public domain, or a name your
LAN DNS resolves — then remove the half-initialised volume and start again:

```bash
docker compose down --timeout 120
docker volume rm seafile-data seafile-database
docker compose up -d --wait --wait-timeout 900
```

Only do this while the installation is empty; on a working instance the same
command destroys every library.

### The container stays unhealthy for several minutes

The first start creates three databases, generates the configuration into the
data volume, and then starts Seahub, which is why the health check allows a five
minute start period. Watch the progress instead of restarting:

```bash
docker compose logs --follow seafile
docker compose ps
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q seafile)"
```

`502` from the published port during that window is normal: nginx is up before
Seahub is.

### Seahub cannot reach the database or the cache

```bash
docker compose logs --tail=200 db cache
docker compose exec db mariadb --user=root --password="$SEAFILE_DB_ROOT_PASSWORD" -e "SHOW DATABASES;"
```

The credentials are written into `conf/seafile.conf` and `conf/seahub_settings.py`
inside the data volume during setup. Changing `SEAFILE_DB_PASSWORD` or
`SEAFILE_CACHE_PASSWORD` in `.env` afterwards does not rewrite those files, so
either restore the old value or edit the generated configuration to match.

### Links, e-mail, or clients point at the wrong address

`SEAFILE_SERVER_HOSTNAME` and `SEAFILE_SERVER_PROTOCOL` are baked into the
generated configuration at first start. To move to another domain, edit
`conf/ccnet.conf` (`SERVICE_URL`), `conf/seahub_settings.py`
(`FILE_SERVER_ROOT`, `SERVICE_URL`), and `conf/seafile.conf` inside the volume,
then restart:

```bash
docker compose exec seafile grep -R "example.com" /shared/seafile/conf
docker compose restart seafile
```

### Uploads fail at a certain size or time out

The proxy is the usual cause: the samples set `client_max_body_size 0`, disable
request buffering, and raise the read and send timeouts because file blocks pass
through the same origin. A `413` comes from the proxy, a `500` after several
minutes usually means the timeout fired mid-transfer.

### Downloads or uploads return 400 from /seafhttp/

That path is the Go file server behind the same nginx, and it answers only with
a valid token, so a bare request returning `400` is expected. A real failure
shows in the logs:

```bash
docker compose exec seafile tail -n 100 /shared/logs/seafile/seafile.log
docker compose exec seafile tail -n 100 /shared/logs/seahub/seahub.log
```

### An encrypted library cannot be opened

Client-side encrypted libraries are decrypted with a password the server never
stores. There is no administrative recovery: a lost library password means the
data stays encrypted, even though the blocks are present in the backup.

### The reverse proxy returns 502

On the host, run `curl -I http://127.0.0.1:8000/accounts/login/`. If that
answers, the proxy is looking at the wrong upstream: inside a proxy container
`127.0.0.1` is the proxy itself, so use a host gateway address or a shared
Docker network. If it does not answer, start from the health-check section above.
