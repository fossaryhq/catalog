### 1. Check the server

Use Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. Allocate
at least 1 CPU, 512 MB RAM, and 5 GB disk; 1 GB RAM plus space for repositories,
packages, and backups is recommended.

```bash
docker --version
docker compose version
```

### 2. Configure the recipe

```bash
mkdir -p ~/services/gitea
cd ~/services/gitea
cp .env.example .env
chmod 600 .env
openssl rand -base64 36
```

Put the generated value in `POSTGRES_PASSWORD`, replace `git.example.com`, and
never publish `.env`. `GITEA_HTTP_PORT` and `GITEA_SSH_PORT` select local ports;
`GITEA_DOMAIN`, `GITEA_SSH_DOMAIN`, and `GITEA_ROOT_URL` define public addresses;
the `POSTGRES_*` variables configure the database; the volume variables name
persistent storage; `GITEA_BACKUP_DIR` selects backup storage.

### 3. Start Gitea and create an administrator

```bash
docker compose config
docker compose pull
docker compose up -d --wait
curl --fail http://127.0.0.1:3000/api/healthz
read -rsp 'Administrator password: ' GITEA_ADMIN_PASSWORD
docker compose exec gitea gitea admin user create --admin --must-change-password --username admin --email admin@example.com --password "$GITEA_ADMIN_PASSWORD"
unset GITEA_ADMIN_PASSWORD
```

The password is not stored in shell history, but is briefly passed to the
process inside the container; change it immediately in the UI. Open registration
is disabled. Gitea persists its data under `/data`.

### VPS deployment

<!-- coverage:deployment-vps -->

Keep both bindings on `127.0.0.1` and expose web only through HTTPS. Test SSH
through `ssh -L 2222:127.0.0.1:2222 user@server`, then `ssh -p 2222 git@localhost`.
To expose Git over SSH publicly, change only its Compose binding to a specific
VPS address such as `${SERVER_IP}:${GITEA_SSH_PORT}:22`, document `SERVER_IP` in
`.env`, and allow that TCP port through the firewall. Keep port 3000 local.

### Trusted LAN access

<!-- coverage:deployment-lan -->

Prefer a VPN or SSH tunnel. If the proxy runs on another LAN host, bind web to a
specific private server address and allow only the proxy through the firewall.
Do not use `0.0.0.0` without network restrictions.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Replace the domain in `.env` and one file under `proxy/`. Caddy obtains a
certificate, Nginx expects Certbot files, and Traefik uses the `letsencrypt`
resolver. The proxy must preserve the URI and forward `Host`,
`X-Forwarded-Proto`, and the client address. A containerized Traefik needs a
reachable host gateway instead of `127.0.0.1`.

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops Gitea, runs a native `pg_dump`, archives the complete data
volume, and starts the service again. Stopping is required: the repositories on
disk and the database rows describing them are consistent with each other only
while nothing writes. The archive lands in `GITEA_BACKUP_DIR`. Encrypt it
because it contains private code, keys, and configuration. Keep an off-server
copy and test restores regularly.

### Restore

<!-- coverage:restore -->

Restore irreversibly replaces the data volume and database. The script takes an
emergency copy of the current state before replacing it. Use the same Gitea
version, check `.env`, then:

```bash
./restore.sh ./backups/gitea-YYYYMMDDTHHMMSSZ.tar
docker compose ps
curl --fail http://127.0.0.1:3000/api/healthz
```

The script finishes with `gitea admin regenerate hooks`: hook scripts embed
absolute paths and the binary version, so they must be rewritten after the data
directory is replaced. The procedure has not passed a practical restore test;
test it on a separate server first.

### Update

<!-- coverage:update -->

Back up first and read the release notes and upgrade guide. The image is pinned
in `compose.yaml`: replace `1.27.3` with a reviewed exact version, update the
exact PostgreSQL tag if needed, then run
`docker compose pull && docker compose up -d --wait`. Do not switch between
rootful and rootless images because their data layouts are incompatible.

### Rollback

<!-- coverage:rollback -->

Never run an old image over a migrated database. Restore the previous exact
Gitea and PostgreSQL tags, then restore the entire pre-update directory using the
procedure above. Rolling back migrations without a synchronized file and
database backup is unsafe.

### Stop and remove

<!-- coverage:removal -->

`docker compose down` preserves data. After verifying an external backup, remove
all data with:

```bash
docker compose down
docker volume rm gitea-data gitea-database
rm -rf ~/services/gitea
```

Sources: [official Docker installation](https://docs.gitea.com/installation/install-with-docker),
[backup and restore](https://docs.gitea.com/administration/backup-and-restore),
[reverse proxies](https://docs.gitea.com/administration/reverse-proxies), and
[upgrades](https://docs.gitea.com/installation/upgrade-from-gitea).
