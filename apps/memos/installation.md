## Requirements and preparation

Use 64-bit Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. Plan for one CPU core, 256 MB RAM (512 MB recommended), and 1 GB disk plus notes and attachments.

```bash
mkdir -p ~/services/memos
cd ~/services/memos
# Copy all recipe files, including config/, proxy/, and the scripts here.
cp .env.example .env
chmod 600 .env
# These two policy files contain no secrets and must be readable by UID 10001.
chmod 755 config
chmod 644 config/memos-instance-setting-*.json
```

| Parameter | Meaning |
| --- | --- |
| `MEMOS_VERSION` | Exact Docker tag, initially `0.31.0`, without `v`. |
| `MEMOS_PORT` | Loopback host port, default `5230`. |
| `MEMOS_URL` | Canonical browser URL, initially `http://localhost:5230`; use the external HTTPS URL behind a proxy. |
| `MEMOS_TRUSTED_PROXIES` | `none` for direct access. For a header-rewriting HTTPS proxy use its IP/CIDR, or `private` only when every reachable private intermediary is trusted. |
| `MEMOS_DATA_VOLUME` | Named volume for SQLite, local files, and persistent instance secrets. |
| `TZ` | IANA time zone, default `Etc/UTC`. |
| `MEMOS_BACKUP_DIR` | Optional absolute backup directory; defaults to `backups/` beside the recipe. |

The scripts source `.env` as trusted shell configuration. Keep it private. `config/` contains two deployment-owned settings: GENERAL disables registration and ACCESS makes the instance private. They override database/UI settings and require a container restart after changes. Keep this directory with the recipe.

## Start and create the administrator

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait --wait-timeout 300
curl --fail http://127.0.0.1:5230/healthz
```

From another computer, first run `ssh -L 5230:127.0.0.1:5230 user@server`. Open `http://localhost:5230`, create the first account, and choose a unique password **before exposing the proxy**. The first account is administrator; there is no default password. Public registration stays disabled afterward. Add later users in administrator settings. Choose the interface language and theme in account settings.

The official entrypoint fixes volume ownership and drops to UID/GID 10001. The root filesystem is read-only; the data volume and `/tmp` are writable. SMTP, SSO, AI providers, remote storage, and webhooks are not configured.

## VPS

<!-- coverage:deployment-vps -->

Complete administrator setup through the tunnel first. Set `MEMOS_URL=https://notes.example.com`, configure an HTTPS proxy, and allow only SSH/HTTP/HTTPS through the host firewall. Keep port 5230 on loopback. Encrypt backups and store a copy off-server.

## Trusted local network

<!-- coverage:deployment-lan -->

Use the SSH tunnel for personal access. Shared LAN access should use an HTTPS proxy. If you change the published address to a private IP, restrict it with a firewall and keep `MEMOS_TRUSTED_PROXIES=none` unless a trusted header-rewriting proxy is actually in the path. Set the canonical URL to the address users open.

## Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Use one sample from `proxy/`: Caddy obtains certificates, Nginx needs certificate paths, and Traefik needs the `websecure` entry point and `letsencrypt` resolver. Samples run on the host and forward to `127.0.0.1:5230`; containerized proxies need a shared network and internal port 5230.

Set the external `MEMOS_URL`. Trust only the proxy's IP/CIDR; `private` also trusts loopback and private ranges, so use it only with the loopback binding and a proxy that overwrites forwarded headers. Restart with `docker compose up -d --wait --wait-timeout 300`. The Nginx sample allows 50 MB requests; Memos separately defaults to a 30 MB upload limit.

## Backup

<!-- coverage:backup -->

```bash
./backup.sh
```

Writers stop while the script archives the complete volume, active `.env`, Compose file, and `config/`. The single private archive is `backups/memos-<timestamp>.tar`. A running app is restarted; an already stopped app stays stopped. Encrypt the archive and copy it off-server: it contains accounts, notes, attachments, and instance/session secrets. Do not copy only a live SQLite file or substitute a personal export.

## Restore

<!-- coverage:restore -->

**Restore replaces the entire app volume.** Use only trusted archives and the matching app version. On a fresh host, copy the recipe and compare archived `configuration.env` and `config.tar.gz` with the active `.env` and `config/` first. Archived configuration is not activated automatically.

```bash
docker compose up -d --wait --wait-timeout 300
./restore.sh ./backups/memos-TIMESTAMP.tar
curl --fail http://127.0.0.1:5230/healthz
```

The script validates the payload before replacement and creates a safety backup. A replacement failure leaves the app stopped. Sign in, open a private memo, and download an attachment after recovery. The amd64 smoke removes the original volume before restoring and verifies those operations.

## Update

<!-- coverage:update -->

Read release notes, create a backup, and copy it off-server. Set `MEMOS_VERSION` to the reviewed exact tag, then:

```bash
docker compose pull
docker compose up -d --wait --wait-timeout 300
docker compose logs --tail=100 memos
```

Migrations run at startup. The 0.x API can change between minor versions: check client/integration compatibility. Version 0.31 removes RSS and expands administrator access. Never use `latest` or assume an older client works with a new API.

## Rollback

<!-- coverage:rollback -->

Do not start an older image on a migrated database. Keep a pre-update backup, stop the app, set the old exact version in `.env`, pull, and recreate without starting:

```bash
docker compose stop memos
# Edit MEMOS_VERSION and compare the matching config/ now.
docker compose pull memos
docker compose create memos
./restore.sh ./backups/memos-BEFORE-UPDATE.tar
```

The safety backup can read the stopped container's volume without starting the old app on new data. Restore the complete matching archive, then verify login, a memo, and a file.

## Stop and remove

<!-- coverage:removal -->

`docker compose down` removes containers and retains the volume. After verifying an encrypted off-server backup, `docker compose down --volumes` permanently removes accounts, notes, and attachments. Deleting the recipe directory also deletes local backups and configuration.

Sources: [deployment](https://usememos.com/docs/deploy), [v0.31.0](https://github.com/usememos/memos/releases/tag/v0.31.0), [configuration provisioning](https://github.com/usememos/memos/blob/v0.31.0/docs/configuration-provisioning.md).
