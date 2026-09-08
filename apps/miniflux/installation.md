### 1. Check the Ubuntu or Debian server

Use Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. One CPU
core, 512 MB RAM, and 2 GB disk are enough for a few hundred feeds; the database
grows with retained entries and downloaded icons. The official image declares
amd64 and arm64.

```bash
docker --version
docker compose version
```

### 2. Prepare the recipe and two independent secrets

```bash
mkdir -p ~/services/miniflux
cd ~/services/miniflux
cp .env.example .env
chmod 600 .env
admin_password="$(openssl rand -hex 24)"
db_password="$(openssl rand -hex 32)"
sed -i "s|^MINIFLUX_ADMIN_PASSWORD=.*|MINIFLUX_ADMIN_PASSWORD=$admin_password|" .env
sed -i "s|^MINIFLUX_DB_PASSWORD=.*|MINIFLUX_DB_PASSWORD=$db_password|" .env
echo "administrator password: $admin_password"
unset admin_password db_password
```

The database password ends up inside `DATABASE_URL`, so keep it alphanumeric: a
`@`, `/`, or `#` would break the connection string. The administrator password
must be at least 12 characters. Store both in a password manager; the
administrator password is shown once here and is not recoverable from the
database.

Every `.env` variable:

- `MINIFLUX_PORT` is the local web port, default `8080`;
- `MINIFLUX_BASE_URL` is the exact public URL without a trailing `/`; links, OAuth2 redirects, and the Google Reader endpoint are derived from it;
- `MINIFLUX_ADMIN_USER` and `MINIFLUX_ADMIN_PASSWORD` create the first account on the first start;
- `MINIFLUX_DB_PASSWORD` is an alphanumeric PostgreSQL password;
- `MINIFLUX_DB_NAME` and `MINIFLUX_DB_USER` are the database and role names, changed only before the first start;
- `MINIFLUX_POLLING_FREQUENCY` is the poller interval in minutes;
- `MINIFLUX_POLLING_PARSING_ERROR_LIMIT` is how many consecutive parse errors disable a feed;
- `MINIFLUX_CLEANUP_ARCHIVE_READ_DAYS` is how long read entries are kept;
- `MINIFLUX_TRUSTED_PROXY_NETWORKS` lists CIDR networks whose forwarded headers are trusted, loopback only by default, and must never be empty;
- `MINIFLUX_LOG_LEVEL` is `error`, `warning`, `info`, or `debug`;
- `MINIFLUX_TIME_ZONE` is an IANA time zone;
- `MINIFLUX_DB_VOLUME` names the PostgreSQL volume;
- `MINIFLUX_BACKUP_DIR` selects the host backup directory.

`RUN_MIGRATIONS` and `CREATE_ADMIN` are pinned to `1` in the recipe. Both are
idempotent: migrations run at every start and the administrator is created only
while the user table is empty.

### 3. Start and sign in

```bash
docker compose config
docker compose pull
docker compose up -d --wait --wait-timeout 600
docker compose ps
curl --fail http://127.0.0.1:8080/healthcheck
```

`/healthcheck` answers `OK` only after the database connection works, so a
successful call means the migrations finished. Sign in at `MINIFLUX_BASE_URL`
with `MINIFLUX_ADMIN_USER`, then add feeds or import an OPML file from
Settings → Import.

### VPS deployment

<!-- coverage:deployment-vps -->

Keep `127.0.0.1:${MINIFLUX_PORT}:8080`; only an HTTPS proxy on the host can
reach the application. PostgreSQL has no published port. Allow SSH, HTTP, and
HTTPS through the firewall and nothing else. Miniflux polls feeds from the
server, so outbound HTTPS must stay open; if the box also reaches private
services, restrict container egress to public networks.

### Trusted LAN access

<!-- coverage:deployment-lan -->

Prefer `ssh -L 8080:127.0.0.1:8080 user@server` with
`MINIFLUX_BASE_URL=http://localhost:8080` for that route. For permanent LAN
access, replace the localhost bind with one specific private IP, set a matching
`MINIFLUX_BASE_URL`, and restrict the port with a firewall. Do not bind
`0.0.0.0` without network controls: the login form and the Fever API would then
answer on every interface over plain HTTP.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Set `MINIFLUX_BASE_URL=https://reader.example.com`, replace the host in the
Caddy, Nginx, or Traefik example, and recreate the container. The proxy must
forward the `Authorization` header — Caddy and Traefik do it by default, and the
Nginx sample does it explicitly — otherwise the Google Reader and Fever APIs
reject every client. Miniflux needs no WebSocket support. Serving from a subpath
is possible with `BASE_URL`, but a dedicated subdomain avoids rewriting the
static asset paths.

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops the application so no poller writes mid-dump, keeps PostgreSQL
running for a native `pg_dump`, and archives the compressed dump together with
`.env` and `compose.yaml`. Everything Miniflux owns is in that dump: feeds,
entries, enclosures metadata, icons, sessions, and API keys. An OPML export is
not a backup — it lists subscriptions and nothing else. The archive contains
secrets; encrypt it and copy it off the server.

### Restore

<!-- coverage:restore -->

Restore irreversibly replaces the database. Use the same Miniflux and PostgreSQL
versions with the active `.env`:

```bash
./restore.sh ./backups/miniflux-YYYYMMDDTHHMMSSZ.tar
curl --fail http://127.0.0.1:8080/healthcheck
```

The script first backs up the state being replaced, recreates the volume,
restores the dump, and starts the stack. The archived `configuration.env` is
kept for comparison only and is never activated. This procedure has not passed a
practical restore test; rehearse it on a separate server before you rely on it.

### Update Miniflux

<!-- coverage:update -->

Create a backup and read the release notes. Replace the exact
`miniflux/miniflux:2.3.3` tag with a reviewed version, never `latest`, and do
not change PostgreSQL in the same step:

```bash
./backup.sh
docker compose pull
docker compose up -d --wait --wait-timeout 600
curl --fail http://127.0.0.1:8080/healthcheck
docker compose logs --tail=200 miniflux
```

Schema migrations run automatically at startup because `RUN_MIGRATIONS=1`.

### PostgreSQL major update

`postgres:18-alpine` is pinned independently of the application. A major change
needs a new data volume: two server majors must never share a cluster directory.
Take a backup, start the new major on an empty volume, and restore the dump with
`restore.sh`. Keep the old volume until the new database is verified.

### Rollback

<!-- coverage:rollback -->

Never start an older Miniflux over a database that newer migrations have already
touched. Restore the previous exact tag together with the pre-update archive:

```bash
docker compose down --timeout 60
./restore.sh ./backups/miniflux-BEFORE-UPDATE.tar
```

After a failed PostgreSQL change, attach the old image to its preserved old
volume, or restore a compatible dump into an empty volume.

### Stop and remove

<!-- coverage:removal -->

`docker compose down` preserves the database. After verifying an off-server
backup, remove everything irreversibly:

```bash
docker compose down
docker volume rm miniflux-database
rm -rf ~/services/miniflux
```

Substitute the actual name when `MINIFLUX_DB_VOLUME` differs.

Sources: [Docker installation](https://miniflux.app/docs/docker.html),
[configuration parameters](https://miniflux.app/docs/configuration.html),
[release 2.3.3](https://github.com/miniflux/v2/releases/tag/2.3.3), and
[PostgreSQL upgrades](https://www.postgresql.org/docs/18/upgrading.html).
