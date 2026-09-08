### 1. Check the Ubuntu or Debian server

Use Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. Allocate
at least 2 CPUs, 4 GB RAM, and 4 GB swap; 8 GB RAM is recommended for large
files and indexing. Disk must hold originals, previews, sidecars, and backups.

```bash
docker --version
docker compose version
free -h && df -h /srv
```

### 2. Prepare directories and secrets

```bash
mkdir -p ~/services/photoprism
sudo mkdir -p /srv/photoprism/{originals,storage,backups}
sudo chown -R "$(id -u):$(id -g)" /srv/photoprism
cd ~/services/photoprism
cp .env.example .env
chmod 600 .env
sed -i "s|^PHOTOPRISM_ADMIN_PASSWORD=.*|PHOTOPRISM_ADMIN_PASSWORD=$(openssl rand -base64 36 | tr -d '/+=')|" .env
sed -i "0,/^PHOTOPRISM_DATABASE_PASSWORD=.*/s||PHOTOPRISM_DATABASE_PASSWORD=$(openssl rand -hex 32)|" .env
sed -i "s|^PHOTOPRISM_DATABASE_ROOT_PASSWORD=.*|PHOTOPRISM_DATABASE_ROOT_PASSWORD=$(openssl rand -hex 32)|" .env
sed -i 's|^PHOTOPRISM_ORIGINALS_PATH=.*|PHOTOPRISM_ORIGINALS_PATH=/srv/photoprism/originals|' .env
sed -i 's|^PHOTOPRISM_STORAGE_PATH=.*|PHOTOPRISM_STORAGE_PATH=/srv/photoprism/storage|' .env
sed -i 's|^PHOTOPRISM_BACKUP_DIR=.*|PHOTOPRISM_BACKUP_DIR=/srv/photoprism/backups|' .env
sed -i "s|^PHOTOPRISM_UID=.*|PHOTOPRISM_UID=$(id -u)|" .env
sed -i "s|^PHOTOPRISM_GID=.*|PHOTOPRISM_GID=$(id -g)|" .env
```

Every `.env` variable:

- `PHOTOPRISM_VERSION` is the exact official image tag;
- `PHOTOPRISM_PORT` is the local web port;
- `PHOTOPRISM_SITE_URL` is the public URL with a trailing `/`;
- `PHOTOPRISM_ADMIN_USER` and `PHOTOPRISM_ADMIN_PASSWORD` form the initial administrator account;
- `PHOTOPRISM_DEFAULT_LOCALE` selects the initial interface language;
- `PHOTOPRISM_ORIGINALS_PATH` holds original photos and videos;
- `PHOTOPRISM_STORAGE_PATH` holds previews, cache, sidecars, configuration, and dumps;
- `PHOTOPRISM_BACKUP_DIR` is the local backup directory used by `backup.sh`;
- `PHOTOPRISM_UID` and `PHOTOPRISM_GID` are the user the image runs the server as; they must match the owner of the directories above;
- `PHOTOPRISM_INIT` is empty by default; setting `tensorflow` downloads a CPU-tuned TensorFlow build (~500 MB) on every container re-creation and holds the web server back until it lands;
- `PHOTOPRISM_DATABASE_NAME`, `PHOTOPRISM_DATABASE_USER`, and `PHOTOPRISM_DATABASE_PASSWORD` configure the application database account;
- `PHOTOPRISM_DATABASE_ROOT_PASSWORD` is used only for MariaDB administration and restore;
- `PHOTOPRISM_DATABASE_VOLUME` names the MariaDB volume;
- `TZ` is an IANA time zone.

### 3. Start PhotoPrism

```bash
docker compose config
docker compose pull
docker compose up -d --wait
docker compose ps
curl --fail http://127.0.0.1:2342/api/v1/status
```

Open `http://localhost:2342` through an SSH tunnel and sign in with `.env`:

```bash
ssh -L 2342:127.0.0.1:2342 user@server.example
```

### VPS deployment

<!-- coverage:deployment-vps -->

Keep the `127.0.0.1` binding, do not publish MariaDB, and allow only SSH, HTTP,
and HTTPS through the firewall. Set
`PHOTOPRISM_SITE_URL=https://photos.example.com/`, recreate the container, and
expose it only through an HTTPS reverse proxy.

### Trusted LAN access

<!-- coverage:deployment-lan -->

Without TLS, use an SSH tunnel or VPN. For permanent LAN access, replace
`127.0.0.1` in `compose.yaml` with a specific private address, set the matching
origin in `PHOTOPRISM_SITE_URL`, and restrict the port with a firewall. Do not
use `0.0.0.0` without network controls.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Replace `photos.example.com` in one file under `proxy/`. Caddy obtains a
certificate, Nginx expects Certbot files, and Traefik uses the `letsencrypt`
resolver. For a containerized proxy, localhost means the proxy itself; use a
reachable host gateway. After changing the URL, run:

```bash
docker compose up -d --force-recreate photoprism
curl --fail https://photos.example.com/api/v1/status
```

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops PhotoPrism, dumps MariaDB, and archives the originals and
storage directories into a single `.tar` in `PHOTOPRISM_BACKUP_DIR`. Stopping is
required: an index running during the copy would leave the database describing
files the originals archive does not contain. The root password reaches the
container through `MYSQL_PWD` rather than argv, so it stays out of the process
list. The archive holds photos and passwords: encrypt it, keep an off-server
copy, and test restores. Built-in database dumps in storage do not replace an
originals backup.

### Restore

<!-- coverage:restore -->

Restore irreversibly replaces the originals, storage, and database. The script
takes an emergency copy of the current state before replacing it. Use the same
image versions, check `.env`, then:

```bash
./restore.sh ./backups/photoprism-YYYYMMDDTHHMMSSZ.tar
docker compose ps
curl --fail http://127.0.0.1:2342/api/v1/status
```

The procedure has not passed a practical restore test; test it on a separate
server first.

### Update

<!-- coverage:update -->

Back up, read the release notes, and change `PHOTOPRISM_VERSION` only to a
reviewed exact tag, never `latest`. Update MariaDB separately.

```bash
docker compose pull photoprism
docker compose up -d --wait photoprism
docker compose logs --tail=200 photoprism
```

### Rollback

<!-- coverage:rollback -->

Do not run old PhotoPrism code over a migrated database. Restore the previous
tag and complete pre-update archive, including its dump and storage. Photos
added after that backup are absent; copy them aside before replacing data.

### Stop and remove

<!-- coverage:removal -->

`docker compose down` preserves data. After verifying an external backup,
remove everything irreversibly:

```bash
docker compose down
docker volume rm photoprism-database
sudo rm -rf /srv/photoprism
rm -rf ~/services/photoprism
```

Sources: [Docker Compose](https://docs.photoprism.app/getting-started/docker-compose/),
[configuration](https://docs.photoprism.app/getting-started/config-options/),
[backup](https://docs.photoprism.app/getting-started/advanced/backups/),
[updates](https://docs.photoprism.app/getting-started/updates/), and
[release 260728](https://github.com/photoprism/photoprism/releases/tag/260728-bbde8f452).
