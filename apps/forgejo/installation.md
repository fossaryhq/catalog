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
mkdir -p ~/services/forgejo
cd ~/services/forgejo
cp .env.example .env
chmod 600 .env
openssl rand -base64 36
```

Put the generated value in `POSTGRES_PASSWORD`, replace `git.example.com`, and
never publish `.env`. `FORGEJO_HTTP_PORT` and `FORGEJO_SSH_PORT` select local
ports; `FORGEJO_DOMAIN`, `FORGEJO_SSH_DOMAIN`, and `FORGEJO_ROOT_URL` define
public addresses; the `POSTGRES_*` variables configure the database; the volume
variables name persistent storage; `FORGEJO_BACKUP_DIR` selects archive storage.

### 3. Start Forgejo and create an administrator

```bash
docker compose config
docker compose pull
docker compose up -d --wait
curl --fail http://127.0.0.1:3000/api/healthz
read -rsp 'Administrator password: ' FORGEJO_ADMIN_PASSWORD
docker compose exec forgejo forgejo admin user create --admin --must-change-password --username admin --email admin@example.com --password "$FORGEJO_ADMIN_PASSWORD"
unset FORGEJO_ADMIN_PASSWORD
```

The password is not stored in shell history, but is briefly passed to the
process inside the container; change it immediately in the UI. Open registration
is disabled. Forgejo persists its data under `/var/lib/gitea`.

### VPS deployment

<!-- coverage:deployment-vps -->

Keep both bindings on `127.0.0.1` and expose web only through HTTPS. Test SSH
through `ssh -L 2222:127.0.0.1:2222 user@server`, then `ssh -p 2222 git@localhost`.
To expose Git over SSH publicly, change only its Compose binding to a specific
VPS address such as `${SERVER_IP}:${FORGEJO_SSH_PORT}:2222`, document `SERVER_IP`
in `.env`, and allow that TCP port through the firewall. Keep port 3000 local.

### Trusted LAN access

<!-- coverage:deployment-lan -->

Prefer a VPN or SSH tunnel. If the proxy runs on another LAN host, bind web to a
specific private server address and allow only the proxy through the firewall.
Do not use `0.0.0.0` without network restrictions.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Replace the domain in `.env` and one file under `proxy/`. Caddy obtains a
certificate, Nginx expects Certbot files, and Traefik uses the `letsencrypt`
resolver. Forward `Host`, `X-Forwarded-Proto`, and the client address. A
containerized Traefik needs a reachable host gateway instead of `127.0.0.1`.

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops Forgejo, runs native `pg_dump`, archives the complete data
volume, and starts Forgejo again. This keeps repositories, attachments, and the
database consistent. Encrypt the archive because it contains private code,
keys, and configuration; keep an off-server copy and test restores regularly.

### Restore

<!-- coverage:restore -->

Restore irreversibly replaces the data volume and database. Use the same Forgejo
version, verify `.env`, then run:

```bash
./restore.sh ./backups/forgejo-YYYYMMDDTHHMMSSZ.tar
docker compose ps
curl --fail http://127.0.0.1:3000/api/healthz
```

The procedure has not passed a practical restore test yet; test it on a separate
server first.

### Update

<!-- coverage:update -->

Back up first and read the release notes and upgrade guide. The image is pinned
in `compose.yaml`; replace `16.0.3-rootless` with a reviewed exact version and
run `docker compose pull && docker compose up -d --wait`. A new major series
requires manual review and `forgejo doctor check --all`.

### Rollback

<!-- coverage:rollback -->

Never run an old image over a migrated database. Restore the old image tag and
the complete pre-update archive with `restore.sh`. Database migrations cannot be
rolled back safely without that synchronized backup.

### Stop and remove

<!-- coverage:removal -->

`docker compose down` preserves data. After verifying a backup, remove all data:

```bash
docker compose down
docker volume rm forgejo-data forgejo-database
rm -rf ~/services/forgejo
```

Sources: [Docker and rootless](https://forgejo.org/docs/latest/admin/installation/docker/),
[upgrade and backup](https://forgejo.org/docs/latest/admin/upgrade/), and the
[configuration cheat sheet](https://forgejo.org/docs/latest/admin/config-cheat-sheet/).
