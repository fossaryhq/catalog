### 1. Check your Ubuntu or Debian server

Upstream requires at least 2 CPU cores and 6 GB of RAM and recommends 4 cores
and 8 GB. Budget disk space for the library plus 10–20 % for thumbnails and
transcodes: this recipe stores both originals and generated files. You need
Ubuntu 22.04+ or Debian 12+ with Docker Engine and Docker Compose v2.24+.

```bash
docker --version
docker compose version
nproc && free -m && df -h /srv
```

Since v3 the machine learning container on amd64 requires the x86-64-v2
microarchitecture level. Check it before installing:

```bash
/usr/bin/ld.so --help | grep -m1 x86-64-v2
```

If the line is missing, the ML container will not start: on such a server your
only option is to disable machine learning and lose smart search and face
recognition.

### 2. Prepare the files and variables

Put the recipe files in their own directory and create a private `.env`:

```bash
mkdir -p ~/services/immich
cd ~/services/immich
cp .env.example .env
chmod 600 .env
```

`IMMICH_VERSION` pins the version of every Immich image; `IMMICH_PORT` sets the
local port; `IMMICH_UPLOAD_LOCATION` is the host directory holding originals,
thumbnails, transcodes, and automatic database dumps; `IMMICH_DB_VOLUME` and
`IMMICH_MODEL_CACHE_VOLUME` name the Docker volumes for PostgreSQL and the model
cache; `IMMICH_DB_USERNAME`, `IMMICH_DB_DATABASE_NAME`, and `IMMICH_DB_PASSWORD`
configure database access; `TZ` sets the time zone.

Always replace the database password and point the library at a disk with free
space:

```bash
sed -i "s|^IMMICH_DB_PASSWORD=.*|IMMICH_DB_PASSWORD=$(openssl rand -hex 24)|" .env
sudo mkdir -p /srv/immich/library
sed -i "s|^IMMICH_UPLOAD_LOCATION=.*|IMMICH_UPLOAD_LOCATION=/srv/immich/library|" .env
```

The password may contain only `A-Za-z0-9`. It cannot be changed after the first
start without recreating the database, so set it now.

### 3. Create the administrator

Keep the port on localhost only and start the stack:

```bash
docker compose pull
docker compose up -d
docker compose ps
ssh -L 2283:127.0.0.1:2283 user@server.example
```

The first start takes longer than usual because the server applies database
migrations. Open `http://localhost:2283`, create an account — the first one
becomes the administrator — and complete the setup wizard. Immich has no public
sign-up: the administrator creates other users under Administration → Users.

The Android and iOS apps connect to the same address and add background upload
of new photos.

### Running on a VPS

<!-- coverage:deployment-vps -->

On a VPS keep the `127.0.0.1` bind, block port 2283 from outside, and publish the
service only through an HTTPS reverse proxy. Check the stack and the API:

```bash
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:2283/api/server/ping
```

All four containers must report `healthy`. Machine learning downloads its models
on the first job, so CPU usage is high for the first minutes after an upload —
that is expected.

### Access from a local network

<!-- coverage:deployment-lan -->

Without TLS use an SSH tunnel or a VPN. If the reverse proxy runs on another host
in a trusted LAN, replace `127.0.0.1` in `compose.yaml` with the server's LAN
address and restrict the port to the proxy address in the firewall. Do not
publish Immich on `0.0.0.0` without network restrictions: access to the timeline
means access to the whole photo archive and its geotags.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Replace `photos.example.com` with your single domain in the file you pick from
`proxy/`. `proxy/Caddyfile` obtains a certificate automatically;
`proxy/nginx.conf` expects a Certbot certificate; `proxy/traefik.yaml` uses the
`letsencrypt` resolver. For Traefik in a container, replace `127.0.0.1` with a
host gateway it can reach.

All three samples lift the request body size limit and raise timeouts: without
that, video uploads from a phone break. Verify the external endpoint:

```bash
curl --fail https://photos.example.com/api/server/ping
```

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops `immich-server` and `immich-machine-learning`, takes a
PostgreSQL dump with `pg_dump`, archives the library directory, and starts the
containers again. Upstream considers copying the PostgreSQL data directory
instead of a dump unsafe, so this recipe always uses a dump.

The archive holds originals, thumbnails, and the whole database with metadata and
faces: encrypt it and keep at least one copy off the server. Immich also writes
automatic database dumps to `UPLOAD_LOCATION/backups` — daily at 02:00 keeping
the last 14 by default; they do not replace a copy of the files.

### Restore

<!-- coverage:restore -->

Restoring replaces both the database and the library directory:

```bash
./restore.sh ./backups/immich-YYYYMMDDTHHMMSSZ.tar
docker compose ps
curl --fail http://127.0.0.1:2283/api/server/ping
```

Before replacing anything the script takes a safety copy of the current data,
then removes the database volume and loads the dump into a clean database. That
is an upstream requirement: a dump must not be restored over a schema the server
has already used. The database and the files must come from the same snapshot,
otherwise the timeline will show entries without files.

### Update

<!-- coverage:update -->

Take a backup and read the release notes: Immich regularly ships changes that
require manual steps. Change only the pinned `IMMICH_VERSION`, then run:

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 immich-server
```

Upgrade one version at a time and do not skip major releases: database migrations
assume an upgrade from the previous version.

### Rollback

<!-- coverage:rollback -->

Immich database migrations are irreversible. Starting an older image against a
database already migrated by a newer version makes the server fail to start.
Restore the pinned `IMMICH_VERSION` in `.env` and restore the archive you created
before the update:

```bash
docker compose pull
./restore.sh ./backups/immich-before-update.tar
docker compose ps
```

Photos uploaded after the update are not in that archive. Copy them out of
`UPLOAD_LOCATION` separately before rolling back if you need them.

### Stopping and complete removal

<!-- coverage:removal -->

`docker compose down` removes the containers but keeps the database and the
library. Complete, irreversible removal after verifying a backup:

```bash
docker compose down
docker volume rm immich-database immich-model-cache
sudo rm -rf /srv/immich/library
rm -rf ~/services/immich
```

Sources: [requirements](https://docs.immich.app/install/requirements),
[Docker Compose install](https://docs.immich.app/install/docker-compose),
[environment variables](https://docs.immich.app/install/environment-variables),
[backup and restore](https://docs.immich.app/administration/backup-and-restore),
and [reverse proxy](https://docs.immich.app/administration/reverse-proxy).
