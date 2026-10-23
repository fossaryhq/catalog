## Requirements and preparation

Use 64-bit Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. Budget at least one CPU core, 1 GB RAM (2 GB recommended), and 5 GB disk plus documents. Both images offer amd64 and arm64; this recipe was run on amd64.

```bash
mkdir -p ~/services/bookstack
cd ~/services/bookstack
# Copy the recipe files, including backup.sh, restore.sh, and proxy/ here.
cp .env.example .env
chmod 600 .env
# Generate APP_KEY; paste the whole base64:... value into .env.
printf 'base64:'; openssl rand -base64 32
# Run twice for independent database passwords.
openssl rand -hex 32
openssl rand -hex 32
```

Edit `.env` before starting. All parameters:

| Parameter | Meaning |
| --- | --- |
| `BOOKSTACK_VERSION` | Pinned upstream release, initially `v26.09.2`; the Compose file adds the image's `version-` prefix. |
| `BOOKSTACK_PORT` | Loopback host port, default `6875`. |
| `BOOKSTACK_APP_URL` | Exact browser URL, including scheme and any nonstandard port. Initially `http://localhost:6875`; use the public HTTPS URL behind a proxy. |
| `BOOKSTACK_APP_KEY` | Unique `base64:` key generated above. Preserve it across upgrades and restores. |
| `BOOKSTACK_DB_PASSWORD` | Unique application database password; replace the placeholder. |
| `BOOKSTACK_DB_ROOT_PASSWORD` | Different root database password; replace the placeholder. |
| `PUID`, `PGID` | File ownership IDs used by LinuxServer, default `1000:1000`. |
| `TZ` | IANA time zone, default `Etc/UTC`. |
| `BOOKSTACK_CONFIG_VOLUME` | Named `/config` volume with uploads, private files, app configuration, and themes. |
| `BOOKSTACK_DB_VOLUME` | Named MariaDB volume with accounts, pages, revisions, and settings. |
| `BOOKSTACK_BACKUP_DIR` | Optional absolute backup directory; defaults to `backups/` beside the recipe. |

Do not reuse placeholder secrets or change database passwords in `.env` after initialization without rotating the corresponding database users. The backup scripts source the local `.env` as trusted shell configuration: keep it private and use simple generated values.

## Start and replace the initial account

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait --wait-timeout 600
curl --fail http://127.0.0.1:6875/status
# Set your own email, name, and unique password. --initial replaces the public default account.
docker compose exec bookstack php /app/www/artisan bookstack:create-admin \
  --initial --email=you@example.com --name='Your name' --generate-password
```

Save the generated password securely. The upstream initial credentials are `admin@admin.com` / `password`: replace this account **before** providing network access. Open the exact `BOOKSTACK_APP_URL` and sign in with your new credentials. Change interface language under your account profile; enable MFA in account authentication settings. Do not enable public access or open registration unless you intend to share the content.

## VPS

<!-- coverage:deployment-vps -->

Keep port 6875 on loopback and the database unexposed. Set `BOOKSTACK_APP_URL=https://docs.example.com`, point DNS to the host, configure HTTPS, and allow only SSH/HTTP/HTTPS through the firewall. Replace the default account before enabling the public proxy. Maintain encrypted off-server backups. SMTP and external authentication require additional settings from the upstream documentation.

## Trusted local network

<!-- coverage:deployment-lan -->

For one person use `ssh -L 6875:127.0.0.1:6875 user@server` and open `http://localhost:6875` with the matching `BOOKSTACK_APP_URL`. For shared LAN access use an HTTPS proxy, or bind the published port to one private address and restrict it with a firewall. The browser must use the configured URL; changing only the published port is insufficient.

## Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Use one example from `proxy/`: Caddy manages certificates, Nginx expects existing certificate files, and Traefik expects a `websecure` entry point and `letsencrypt` resolver. These examples run on the host and reach `127.0.0.1:6875`; a containerized proxy needs a shared Docker network and the app's internal port 80 instead. Nginx permits 50 MB requests; PHP's upload limit must also permit the file size you need.

Set the exact external HTTPS URL in `.env` before first start. When changing an existing URL, first back up, change `BOOKSTACK_APP_URL`, recreate the app, then update stored links:

```bash
docker compose up -d --wait --wait-timeout 600
docker compose exec bookstack php /app/www/artisan bookstack:update-url \
  http://localhost:6875 https://docs.example.com
```

## Backup

<!-- coverage:backup -->

```bash
./backup.sh
```

The script stops BookStack writers, dumps MariaDB, and archives `/config`, `.env`, and `compose.yaml` into one private `backups/bookstack-<timestamp>.tar`. MariaDB stays running. An app that was running is restarted even if the backup fails. Encrypt the archive and copy it off-server: it contains documents, attachments, database credentials, and `APP_KEY`. A database dump alone cannot restore uploaded files; a `/config` archive alone cannot restore pages.

## Restore

<!-- coverage:restore -->

**Restore replaces the database and all `/config` data.** Use only your own trusted archives. Start the matching recipe with the original `APP_KEY` and compatible application/database versions. Compare the archived `configuration.env` with `.env` manually; the script never sources or activates the archived file. On a fresh host, create the containers and wait for MariaDB before restoring.

```bash
docker compose up -d --wait --wait-timeout 600
./restore.sh ./backups/bookstack-TIMESTAMP.tar
curl --fail http://127.0.0.1:6875/status
docker compose logs --tail=100 bookstack
```

The script validates required archive members and makes a safety backup before replacing data. If replacement fails, keep the app stopped and repair or restore again. Check both a saved page and an attachment after restoring. The smoke test checks database and file restoration on amd64.

## Update

<!-- coverage:update -->

Read release notes, run `./backup.sh`, and copy the archive off-server. Change `BOOKSTACK_VERSION` to an exact reviewed release, then:

```bash
docker compose pull
docker compose up -d --wait --wait-timeout 600
docker compose logs --tail=100 bookstack
```

Do not use `latest`. Startup applies database migrations. MariaDB has its own pinned version in Compose; review its upgrade procedure separately before changing it.

## Rollback

<!-- coverage:rollback -->

Never run an older BookStack against a database migrated by a newer version. Keep MariaDB running, stop the app, set `BOOKSTACK_VERSION` and `APP_KEY` to the values from before the upgrade, and recreate the app container without starting it:

```bash
docker compose stop bookstack
# Edit .env now: previous exact application version and original APP_KEY.
docker compose pull bookstack
docker compose create bookstack
./restore.sh ./backups/bookstack-BEFORE-UPDATE.tar
curl --fail http://127.0.0.1:6875/status
```

The stopped container lets the safety backup run without launching the old application on the new database. Do not downgrade MariaDB's physical data directory; if its version changed, restore the SQL dump into a clean compatible database volume, preserving the existing volume until recovery is verified.

## Stop and remove

<!-- coverage:removal -->

`docker compose down` stops and removes containers while retaining both data volumes. After verifying an off-server backup, `docker compose down --volumes` permanently deletes the database, documents, uploads, accounts, and configuration. Removing the recipe directory additionally deletes local backups; preserve the archive elsewhere first.

Sources: [installation](https://www.bookstackapp.com/docs/admin/installation/), [LinuxServer image and configuration](https://docs.linuxserver.io/images/docker-bookstack/), [backup and restore](https://www.bookstackapp.com/docs/admin/backup-restore/), [security](https://www.bookstackapp.com/docs/admin/security/), and [system CLI](https://www.bookstackapp.com/docs/admin/system-cli/).
