### 1. Check your Ubuntu or Debian server

For this recipe budget at least 2 CPU cores, 2 GB of RAM, and 20 GB of disk for
the server itself; 4 GB of RAM is recommended. This is a conservative estimate
for the recipe: upstream publishes requirements for PHP and the database but not
for the machine as a whole, and usage depends on the number of users and the
enabled apps. Count storage for the files separately. You need Ubuntu 22.04+ or
Debian 12+ with Docker Engine and Docker Compose v2.24+.

```bash
docker --version
docker compose version
nproc && free -m && df -h /srv
```

### 2. Prepare the files and variables

```bash
mkdir -p ~/services/nextcloud
cd ~/services/nextcloud
cp .env.example .env
chmod 600 .env
sudo mkdir -p /srv/nextcloud/data
sudo chown -R 33:33 /srv/nextcloud/data
sed -i "s|^NEXTCLOUD_DATA_LOCATION=.*|NEXTCLOUD_DATA_LOCATION=/srv/nextcloud/data|" .env
```

Inside the container Nextcloud runs as `www-data` with UID 33, so the data
directory has to belong to that user.

Always replace both example passwords:

```bash
sed -i "s|^NEXTCLOUD_DB_PASSWORD=.*|NEXTCLOUD_DB_PASSWORD=$(openssl rand -hex 24)|" .env
sed -i "s|^NEXTCLOUD_ADMIN_PASSWORD=.*|NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 24)|" .env
```

`NEXTCLOUD_VERSION` pins the image; `NEXTCLOUD_PORT` sets the local port;
`NEXTCLOUD_DATA_LOCATION` is the directory with user files;
`NEXTCLOUD_HTML_VOLUME` and `NEXTCLOUD_DB_VOLUME` name the volumes for the code
and the database; `NEXTCLOUD_DB_*` and `NEXTCLOUD_ADMIN_*` configure database
access and the first account; `NEXTCLOUD_TRUSTED_DOMAINS` lists the domains
allowed to serve the instance; `NEXTCLOUD_TRUSTED_PROXIES` and
`NEXTCLOUD_OVERWRITE_*` are needed behind a reverse proxy; `NEXTCLOUD_PHP_*` set
the PHP limits; `TZ` sets the time zone.

The database password and user can only be changed before the first start: once
PostgreSQL is initialised, the variable will not create a new account.

### 3. Start the stack

```bash
docker compose pull
docker compose up -d
docker compose ps
ssh -L 8080:127.0.0.1:8080 user@server.example
```

The first start takes longer than usual: the container unpacks the code and runs
the installation. The administrator is created automatically from the variables,
so there is no setup wizard in the browser — open `http://localhost:8080` and log
straight in.

Check that background jobs run in their own container rather than through the
browser:

```bash
docker compose exec -u www-data app php occ config:app:get core backgroundjobs_mode
```

The answer must be `cron`.

### Running on a VPS

<!-- coverage:deployment-vps -->

On a VPS keep the `127.0.0.1` bind, block port 8080 from outside, and publish the
service only through an HTTPS reverse proxy. Check the stack:

```bash
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:8080/status.php
```

All four containers must be up, and `app`, `database`, and `redis` must be
`healthy`. Keep in mind that preview generation and background jobs load a small
VPS noticeably: on a single shared core it is worth disabling preview generation
for large files.

### Access from a local network

<!-- coverage:deployment-lan -->

Without TLS use an SSH tunnel or a VPN. If the reverse proxy runs on another host
in a trusted LAN, replace `127.0.0.1` in `compose.yaml` with the server's LAN
address, add that address to `NEXTCLOUD_TRUSTED_DOMAINS`, and restrict the port
to the proxy address in the firewall.

Nextcloud refuses a request from a domain that is not in
`NEXTCLOUD_TRUSTED_DOMAINS`: instead of the interface you get an untrusted domain
message.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Replace `cloud.example.com` with your single domain in the file you pick from
`proxy/`, and put it in `.env`:

```bash
NEXTCLOUD_TRUSTED_DOMAINS=cloud.example.com
NEXTCLOUD_TRUSTED_PROXIES=172.16.0.0/12
NEXTCLOUD_OVERWRITE_PROTOCOL=https
NEXTCLOUD_OVERWRITE_CLI_URL=https://cloud.example.com
```

`proxy/Caddyfile` obtains a certificate automatically; `proxy/nginx.conf`
expects a Certbot certificate; `proxy/traefik.yaml` uses the `letsencrypt`
resolver. For Traefik in a container, replace `127.0.0.1` with a host gateway it
can reach.

All three samples do two things without which Nextcloud misbehaves: they lift the
upload size limit and redirect `/.well-known/carddav` and `/.well-known/caldav`
to `/remote.php/dav` — otherwise calendar and contacts do not connect in
clients.

```bash
docker compose up -d
curl --fail https://cloud.example.com/status.php
```

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script enables maintenance mode, takes a PostgreSQL dump, archives the volume
with the code, apps, and `config.php`, then turns maintenance mode off. Without
maintenance mode the database and file copies can drift apart.

User files are not in the archive: their directory can grow to terabytes and is
better copied incrementally:

```bash
rsync -a --delete /srv/nextcloud/data/ /mnt/backup/nextcloud-data/
```

A full restore needs three parts: the database dump, the code volume, and the
file directory. Keep them consistent, and keep at least one copy off the server.

One detail that trips people up when backing up by hand: the Nextcloud installer
creates a separate PostgreSQL role named `oc_<admin name>` for normal operation,
and the tables belong to it rather than to the user from `.env`. That is why
`backup.sh` dumps the role list alongside the database — without it the dump will
not load into a clean PostgreSQL.

### Restore

<!-- coverage:restore -->

Restoring replaces the database and the code completely:

```bash
./restore.sh ./backups/nextcloud-YYYYMMDDTHHMMSSZ.tar
docker compose ps
curl --fail http://127.0.0.1:8080/status.php
```

Before replacing anything the script takes a safety copy of the current state,
removes the database volume, and loads the dump into a clean database. The user
file directory is untouched: if it was lost, restore it from your own copy before
starting, otherwise Nextcloud shows entries without files.

After a restore it is worth rescanning the files:

```bash
docker compose exec -u www-data app php occ files:scan --all
```

### Update

<!-- coverage:update -->

Take a backup and read the release notes. Upgrade strictly one major version at a
time: you cannot jump from 32 to 34, the installer will stop the transition.

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 app
docker compose exec -u www-data app php occ status
```

After the upgrade, look at Administration → Overview: new recommendations and
warnings appear there when something is configured wrong.

### Rollback

<!-- coverage:rollback -->

Nextcloud database migrations are irreversible: an older image will not start
against a database a newer version has upgraded. Restore the pinned
`NEXTCLOUD_VERSION` in `.env` and restore the archive taken before the update:

```bash
docker compose pull
./restore.sh ./backups/nextcloud-before-update.tar
docker compose up -d
```

Files uploaded after the update stay on disk, but the restored database has no
records of them: bring them back with `occ files:scan --all`.

### Stopping and complete removal

<!-- coverage:removal -->

`docker compose down` removes the containers but keeps the database, the code,
and the files. Complete, irreversible removal after verifying a backup:

```bash
docker compose down
docker volume rm nextcloud-html nextcloud-database
sudo rm -rf /srv/nextcloud/data
rm -rf ~/services/nextcloud
```

Sources: [Docker installation](https://github.com/nextcloud/docker#readme),
[administration manual](https://docs.nextcloud.com/server/latest/admin_manual/),
[reverse proxy](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/reverse_proxy_configuration.html),
[background jobs](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/background_jobs_configuration.html),
[caching and locking](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/caching_configuration.html),
and [backup](https://docs.nextcloud.com/server/latest/admin_manual/maintenance/backup.html).
