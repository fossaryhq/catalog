## Requirements and preparation

Use 64-bit Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. Plan for one CPU core, at least 1 GB RAM (2 GB recommended), and 5 GB disk plus attachments. Images support amd64 and arm64; this recipe was tested on amd64.

```bash
mkdir -p ~/services/vikunja
cd ~/services/vikunja
# Copy the recipe files, including backup.sh, restore.sh, and proxy/ here.
cp .env.example .env
chmod 600 .env
# Run twice, for an independent service secret and database password.
openssl rand -hex 32
openssl rand -hex 32
```

Edit `.env` before starting. Every parameter:

| Parameter | Meaning |
| --- | --- |
| `VIKUNJA_VERSION` | Exact application version, initially `2.7.1`. Do not add `v` to this Docker tag. |
| `VIKUNJA_PORT` | Loopback host port, default `3456`. |
| `VIKUNJA_PUBLIC_URL` | Exact browser URL with scheme, port if needed, and trailing slash. Default `http://localhost:3456/`; use the external HTTPS URL behind a proxy. |
| `VIKUNJA_SECRET` | Random service secret generated above; preserve it across restarts and recovery. |
| `VIKUNJA_DB_PASSWORD` | Different random PostgreSQL password; replace the placeholder before first start. |
| `VIKUNJA_DATA_VOLUME` | App volume with uploaded files under `/data/files`. |
| `VIKUNJA_DB_VOLUME` | PostgreSQL 18 volume mounted at `/var/lib/postgresql`, including its versioned data directory. |
| `TZ` | IANA time zone, default `Etc/UTC`. Set account time zones separately in the app. |
| `VIKUNJA_BACKUP_DIR` | Optional absolute backup directory; defaults to `backups/` beside the recipe. |

The scripts source the active `.env` as trusted shell configuration. Keep it private and use the generated simple values. Changing a database password in `.env` does not rotate an initialized PostgreSQL role's password.

## Start and create your account

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait --wait-timeout 300
curl --fail http://127.0.0.1:3456/health
# Use your username and email; the CLI prompts for a password.
docker compose exec vikunja /app/vikunja/vikunja user create \
  --username=alex --email=you@example.com
```

There is no default account. Open the exact `VIKUNJA_PUBLIC_URL` and sign in with the account you created. Registration stays disabled; create additional accounts through the same CLI. Choose a language and time zone in account settings, and enroll TOTP if desired. The optional Pro web administration panel is not required for these steps. No SMTP or external identity provider is configured.

The `permissions` container exits successfully after assigning the app volume to `1000:1000`; this is expected. The app's root filesystem is read-only, with writable attachments in `/data` and temporary files in `/tmp`.

## VPS

<!-- coverage:deployment-vps -->

Keep port 3456 on loopback and PostgreSQL private. Point a domain to the host, set `VIKUNJA_PUBLIC_URL=https://tasks.example.com/`, configure an HTTPS proxy, and allow only SSH/HTTP/HTTPS through the firewall. Store encrypted backups off-server. Registration is disabled, but each account still needs a unique password and carefully chosen project-sharing permissions.

## Trusted local network

<!-- coverage:deployment-lan -->

For personal access use `ssh -L 3456:127.0.0.1:3456 user@server` and `http://localhost:3456/` with the matching public URL. For shared LAN access use an HTTPS proxy, or bind the host port to a specific private IP and restrict it with a firewall. Keep PostgreSQL unexposed. The configured public URL must match the address clients actually use.

## Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Use one file from `proxy/`. Caddy obtains certificates; Nginx expects certificate files; Traefik expects a `websecure` entry point and `letsencrypt` resolver. Samples run on the host and proxy to `127.0.0.1:3456`. A containerized proxy needs a shared network and the app's internal port 3456 instead.

Set the external HTTPS URL, including its trailing slash, in `.env` and run `docker compose up -d --wait --wait-timeout 300` after a URL change. Nginx permits 50 MB requests, but Vikunja's default maximum file size is 20 MB; both limits apply. OIDC and desktop clients must use the same reachable application URL.

## Backup

<!-- coverage:backup -->

```bash
./backup.sh
```

The script stops Vikunja, dumps PostgreSQL, and archives the app volume, `.env`, and Compose file into one private `backups/vikunja-<timestamp>.tar`. An app that was running is restarted; an already stopped app stays stopped. PostgreSQL keeps running. The database and attachments describe the same stopped state. Encrypt the complete archive and copy it off-server: it includes credentials and private user data. A database dump alone cannot restore file contents.

## Restore

<!-- coverage:restore -->

**Restore replaces the database's public schema and the app volume.** Use only your own trusted archives and matching application/database versions. Compare archived `configuration.env` with `.env` manually, preserving its service secret; the script does not activate the archived environment.

```bash
# On a fresh host, initialize the matching recipe first.
docker compose up -d --wait --wait-timeout 300
./restore.sh ./backups/vikunja-TIMESTAMP.tar
curl --fail http://127.0.0.1:3456/health
docker compose logs --tail=100 vikunja database
```

Before replacement the script validates the archive and makes a safety backup. A replacement failure leaves the app stopped; repair the problem or restore again before starting it. Afterward, sign in, open a task, and download an attachment. The amd64 smoke exercises this path with a real uploaded file.

## Update

<!-- coverage:update -->

Read release notes, run `./backup.sh`, and copy the archive off-server. Set `VIKUNJA_VERSION` to the exact reviewed Docker tag:

```bash
docker compose pull
docker compose up -d --wait --wait-timeout 300
docker compose logs --tail=100 vikunja
```

Do not use `latest`. Migrations run at startup. PostgreSQL's version is pinned separately in Compose; review its upgrade procedure before changing it.

## Rollback

<!-- coverage:rollback -->

Never run an older app against a database migrated by a newer release. Keep PostgreSQL running, stop Vikunja, set its previous exact version and original service secret in `.env`, then recreate its container without starting it:

```bash
docker compose stop vikunja
# Edit .env now: previous VIKUNJA_VERSION and original VIKUNJA_SECRET.
docker compose pull vikunja
docker compose create vikunja
./restore.sh ./backups/vikunja-BEFORE-UPDATE.tar
curl --fail http://127.0.0.1:3456/health
```

The safety backup can run against the stopped container without launching the old app on migrated data. Do not downgrade a PostgreSQL physical data directory. If the database version changed, restore the SQL into a clean compatible database volume and preserve the existing one until recovery is verified.

## Stop and remove

<!-- coverage:removal -->

`docker compose down` removes containers while retaining both volumes. After verifying an off-server backup, `docker compose down --volumes` permanently deletes tasks, accounts, settings, and attachments. Removing the recipe directory also removes local backups; keep a protected copy elsewhere first.

Sources: [documentation](https://vikunja.io/docs/), [CLI](https://vikunja.io/docs/cli/), [configuration](https://vikunja.io/docs/config-options/), [backup/restore](https://vikunja.io/docs/backup-restore/), and [PostgreSQL Docker image](https://hub.docker.com/_/postgres).
