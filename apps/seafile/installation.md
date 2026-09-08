### 1. Check the Ubuntu or Debian server

Use Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. Upstream
asks for at least 2 CPU cores and 2 GB RAM; plan 4 GB and disk for the whole
library collection plus the file history each library keeps. The published image
is amd64 only, so an ARM board is not a supported target for this recipe.

```bash
docker --version
docker compose version
```

### 2. Prepare the recipe and four independent secrets

```bash
mkdir -p ~/services/seafile
cd ~/services/seafile
cp .env.example .env
chmod 600 .env
admin_password="$(openssl rand -hex 24)"
db_root_password="$(openssl rand -hex 32)"
db_password="$(openssl rand -hex 32)"
jwt_key="$(openssl rand -hex 32)"
cache_password="$(openssl rand -hex 32)"
sed -i "s|^SEAFILE_ADMIN_PASSWORD=.*|SEAFILE_ADMIN_PASSWORD=$admin_password|" .env
sed -i "s|^SEAFILE_DB_ROOT_PASSWORD=.*|SEAFILE_DB_ROOT_PASSWORD=$db_root_password|" .env
sed -i "s|^SEAFILE_DB_PASSWORD=.*|SEAFILE_DB_PASSWORD=$db_password|" .env
sed -i "s|^SEAFILE_JWT_PRIVATE_KEY=.*|SEAFILE_JWT_PRIVATE_KEY=$jwt_key|" .env
sed -i "s|^SEAFILE_CACHE_PASSWORD=.*|SEAFILE_CACHE_PASSWORD=$cache_password|" .env
echo "administrator password: $admin_password"
unset admin_password db_root_password db_password jwt_key cache_password
```

The JWT key must be at least 32 characters. All five values must differ and must
stay stable: the server stores its generated configuration inside the data
volume and expects the same database and cache credentials on every start.

Set the public name before the first start:

```bash
sed -i "s|^SEAFILE_SERVER_HOSTNAME=.*|SEAFILE_SERVER_HOSTNAME=files.example.com|" .env
sed -i "s|^SEAFILE_ADMIN_EMAIL=.*|SEAFILE_ADMIN_EMAIL=you@example.com|" .env
```

Every `.env` variable:

- `SEAFILE_PORT` is the local web port, default `8000`;
- `SEAFILE_SERVER_HOSTNAME` is the public host name without scheme or slash, and the setup script rejects `localhost`;
- `SEAFILE_SERVER_PROTOCOL` is the scheme the service is reached by, `https` behind the proxy examples;
- `SEAFILE_ADMIN_EMAIL` and `SEAFILE_ADMIN_PASSWORD` create the first account on the first start only;
- `SEAFILE_DB_ROOT_PASSWORD` is the MariaDB root password, used for setup and for dumps;
- `SEAFILE_DB_PASSWORD` is the password of the `seafile` database role;
- `SEAFILE_JWT_PRIVATE_KEY` signs internal service tokens and must be 32 characters or longer;
- `SEAFILE_CACHE_PASSWORD` protects the Valkey cache, which is not published to the network;
- `SEAFILE_DB_USER` is the database role name, changed only before the first start;
- `SEAFILE_TIME_ZONE` is an IANA time zone;
- `SEAFILE_DATA_VOLUME` and `SEAFILE_DB_VOLUME` name the object-store and database volumes;
- `SEAFILE_BACKUP_DIR` selects the host backup directory.

### 3. Start and sign in

```bash
docker compose config
docker compose pull
docker compose up -d --wait --wait-timeout 900
docker compose ps
curl --fail --silent --output /dev/null http://127.0.0.1:8000/accounts/login/
```

The first start is slow: the container creates `ccnet_db`, `seafile_db`, and
`seahub_db`, generates the configuration into the data volume, and only then
starts Seahub behind its own nginx. Sign in at the public address with
`SEAFILE_ADMIN_EMAIL`, then install the desktop or mobile client and connect it
to the same address.

### VPS deployment

<!-- coverage:deployment-vps -->

Keep `127.0.0.1:${SEAFILE_PORT}:80`; only an HTTPS proxy on the host can reach
the server. MariaDB and the cache have no published ports. Allow SSH, HTTP, and
HTTPS through the firewall. Set `SEAFILE_SERVER_PROTOCOL=https` and create the
DNS record before the first start: the value is written into the generated
configuration, and clients that were configured with the wrong scheme keep using
it.

### Trusted LAN access

<!-- coverage:deployment-lan -->

Prefer `ssh -L 8000:127.0.0.1:8000 user@server`. A permanent LAN deployment needs
a resolvable host name — the setup script refuses `localhost`, so use a name
your LAN DNS answers for, set `SEAFILE_SERVER_PROTOCOL=http`, replace the
localhost bind with one specific private IP, and restrict the port with a
firewall. Client-side encrypted libraries still protect their contents, but
everything else, including session cookies, travels in clear text on that route.

### Domain, HTTPS, and uploads

<!-- coverage:deployment-domain-https -->

Set `SEAFILE_SERVER_HOSTNAME=files.example.com` and
`SEAFILE_SERVER_PROTOCOL=https`, then replace the host in the Caddy, Nginx, or
Traefik example. The proxy must not cap the request body — file blocks travel
through the same origin, which is why the Nginx sample sets
`client_max_body_size 0` and disables request buffering — and must allow long
transfers, so keep the read and send timeouts high. Changing the host name after
the first start requires editing `conf/ccnet.conf`, `conf/seahub_settings.py`,
and `conf/seafile.conf` inside the data volume.

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops Seafile, dumps all three databases with `mariadb-dump`, archives
the whole `/shared` volume with the object store, and stores `.env` and
`compose.yaml` next to them. Both halves are needed: a database dump alone
restores an index that points at file blocks that are no longer there. The
archive contains every file and every secret; encrypt it and copy it off the
server.

### Restore

<!-- coverage:restore -->

Restore irreversibly replaces the object store and all three databases. Use the
same Seafile and MariaDB versions with the active `.env`:

```bash
./restore.sh ./backups/seafile-YYYYMMDDTHHMMSSZ.tar
curl --fail --silent --output /dev/null http://127.0.0.1:8000/accounts/login/
```

The script first backs up the state being replaced, recreates both volumes,
unpacks the object store, imports the dump, and starts the server. Desktop
clients that synced after the backup will re-upload their local changes; check
one client before letting the rest reconnect. This procedure has not passed a
practical restore test; rehearse it on a separate server first.

### Update Seafile

<!-- coverage:update -->

Back up first and read the upstream upgrade notes for the exact version pair.
Minor updates inside one major series are a tag change:

```bash
./backup.sh
docker compose pull
docker compose up -d --wait --wait-timeout 900
docker compose logs --tail=200 seafile
```

A major upgrade is not: Seafile runs versioned upgrade scripts and expects you
to move one major version at a time, from the latest minor of the current
series. Do not jump from 12.x to 14.x, and never change MariaDB in the same
step. Replace the exact `seafileltd/seafile-mc:13.0.25` tag with a reviewed
version, never a `-latest` or `-testing` tag.

### Rollback

<!-- coverage:rollback -->

Never start an older Seafile over databases a newer version has already
upgraded. Restore the previous exact tag together with the pre-update archive:

```bash
docker compose down --timeout 120
./restore.sh ./backups/seafile-BEFORE-UPDATE.tar
```

After a failed MariaDB change, attach the old image to its preserved old volume,
or import a compatible dump into an empty volume.

### Stop and remove

<!-- coverage:removal -->

`docker compose down` preserves both volumes. After verifying an off-server
backup, remove everything irreversibly:

```bash
docker compose down
docker volume rm seafile-data seafile-database
rm -rf ~/services/seafile
```

Substitute actual names when the volume variables differ. Desktop clients keep
their own local copies of every synced library; remove them separately if the
data must be gone everywhere.

Sources: [Seafile CE with Docker](https://manual.seafile.com/13.0/setup/setup_ce_by_docker/),
[upstream compose file](https://manual.seafile.com/13.0/repo/docker/ce/seafile-server.yml),
[backup and recovery](https://manual.seafile.com/13.0/administration/backup_recovery/), and
[OAuth authentication](https://manual.seafile.com/13.0/config/oauth/).
