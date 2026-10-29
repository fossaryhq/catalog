# Install and maintain Firefly III

<!-- coverage:linux -->
## Ubuntu and Debian

Use Ubuntu 24.04/26.04 LTS or Debian 12/13 with Docker Engine and Docker Compose v2.24 or newer, following [Docker's installation guide](https://docs.docker.com/engine/install/). Commands run from this recipe directory. Install `openssl`; Python 3 and curl are needed only for the smoke test. Docker access grants administrative control of the host.

```bash
cp .env.example .env
chmod 600 .env
openssl rand -hex 16  # FIREFLY_APP_KEY: exactly 32 characters
openssl rand -hex 16  # FIREFLY_CRON_TOKEN: exactly 32 characters
openssl rand -hex 24  # FIREFLY_DB_PASSWORD
```

Paste the three different results into `.env`, set `FIREFLY_SITE_OWNER`, and leave the service bound to loopback for the first registration. The entrypoint rejects the template key, template database password and incorrect key/token lengths before HTTP starts. The administrator password is created in the browser, not in `.env`.

```bash
docker compose --env-file .env config --quiet
docker compose --env-file .env pull
docker compose --env-file .env up -d --wait --wait-timeout 600
docker compose ps
```

<!-- coverage:deployment-vps -->
## VPS and first owner

Create the owner account **before** publishing the proxy. For a remote server, open a tunnel from your computer:

```bash
ssh -L 8088:127.0.0.1:8088 user@server
```

Open `http://localhost:8088`, register with a unique password of at least 16 characters, and finish the account/currency setup. The default single-user mode closes registration after the first account. Enable TOTP in the profile and keep recovery codes offline. Only then enable public HTTPS. Keep PostgreSQL and cron ports unpublished; configure a firewall, updates and encrypted off-server backups.

<!-- coverage:deployment-lan -->
## Trusted LAN or VPN

Use the same tunnel for bootstrap. After registration, replace `127.0.0.1` in the web port mapping with the server's private address, set `FIREFLY_URL=http://<private-address>:8088`, and recreate the services. Restrict access to trusted clients or a VPN. A private address without HTTPS still carries login sessions and financial information in cleartext.

<!-- coverage:deployment-domain-https -->
## Domain and HTTPS

Point `money.example.com` at the server and set `FIREFLY_URL=https://money.example.com`. Set `FIREFLY_TRUSTED_PROXIES` to the exact address or CIDR of your proxy, as seen by the application, then run `docker compose up -d --wait --wait-timeout 600`. Do not use `**` unless all direct access is controlled. Keep `AUTHENTICATION_GUARD=web`; forwarded protocol headers do not enable single sign-on.

<!-- coverage:proxy -->
## Caddy, Nginx and Traefik

`proxy/Caddyfile` routes an HTTPS domain to the loopback port. `proxy/nginx.conf` requires your certificate paths; check with `nginx -t` before reload. `proxy/traefik.yaml` is a dynamic file-provider configuration for an existing Traefik installation with the declared certificate resolver. These examples assume the proxy runs on the Docker host. A containerized proxy must share a controlled network or use a reachable host address; its `127.0.0.1` points to itself.

<!-- coverage:data -->
## Data and every setting

Compose creates project-scoped `database`, `storage` and `uploads` volumes. PostgreSQL 18 stores data under `/var/lib/postgresql`; Laravel storage is `/var/www/html/storage`; the separate upload volume overlays `/var/www/html/storage/upload`. The storage volume includes OAuth signing keys. `.env` contains the attachment/session encryption key; losing `FIREFLY_APP_KEY` can make encrypted data unreadable.

| Variable | Meaning |
| --- | --- |
| `FIREFLY_VERSION` | Application version, `6.7.9`; the image tag is `version-6.7.9`. |
| `FIREFLY_PORT` | Loopback HTTP port, `8088`. |
| `FIREFLY_URL` | External URL including scheme and port, if nonstandard. |
| `FIREFLY_APP_KEY` | Secret of exactly 32 characters; retain for restoration. |
| `FIREFLY_DB_PASSWORD` | Unique PostgreSQL password. Set before first start; changing only `.env` does not change the stored database role password. |
| `FIREFLY_CRON_TOKEN` | Independent 32-character secret for scheduled HTTP jobs. |
| `FIREFLY_SITE_OWNER` | Operator email shown in some errors; use an appropriate contact. |
| `FIREFLY_LANGUAGE` | Initial interface language, `en_US` or `ru_RU`; users may override it. |
| `FIREFLY_TRUSTED_PROXIES` | Trusted proxy IP/CIDR; empty by default. |
| `TZ` | Application timezone, `UTC` by default. The cron service always runs at 03:00 UTC. |

The scripts also accept optional `FOSSARY_ENV_FILE`, `COMPOSE_PROJECT_NAME` and `FIREFLY_BACKUP_DIR`. Defaults are `.env`, project `firefly-iii`, and `backups/`. If you started with a custom `docker compose -p` name, export that exact `COMPOSE_PROJECT_NAME` for every backup and restore command. The daily cron covers recurring transactions and automatic budgets; bank import and backup scheduling are separate operations. SMTP is not configured; mail links go to application logs and must be protected.

<!-- coverage:backup -->
## Backup

```bash
bash backup.sh
```

The script stops cron and the application, creates a logical PostgreSQL dump and two storage archives, includes `.env` and Compose, then restarts only the services that were running. Archives use mode 600 and unique names. Encrypt a copy on another machine and test restoration regularly. Exported transactions are not a complete backup.

<!-- coverage:restore -->
## Restore — replaces financial data

Use only trusted archives. Keep a copy of the old `.env`, especially `FIREFLY_APP_KEY`, and the matching application/database versions. On a new server, start only the database and create the application containers without starting them:

```bash
docker compose up -d --wait database
docker compose create --no-deps firefly cron
```

Then restore:

```bash
bash restore.sh /absolute/path/firefly-iii-<timestamp>.tar
```

The script validates archive members, creates a safety backup, stops writers, recreates the application database, replaces both storage volumes and waits for health. It does not activate the archived `.env`. Check account balances, transactions, attachments and API tokens before reopening access. A failure leaves writers stopped; inspect logs and fix the error before restarting. Recovery onto another server also needs the archived secrets and a corrected external URL.

<!-- coverage:update -->
## Update

Read the [release notes](https://github.com/firefly-iii/firefly-iii/releases) and [upgrade guide](https://docs.firefly-iii.org/how-to/firefly-iii/upgrade/docker/). Save the current `.env`, Compose and a verified backup. Stop cron and the application, change only `FIREFLY_VERSION` to the reviewed pinned version, pull and restart:

```bash
bash backup.sh
docker compose stop cron firefly
# Edit FIREFLY_VERSION in .env; keep the database major version unchanged.
docker compose pull firefly
docker compose up -d --wait --wait-timeout 600
docker compose logs --tail=100 firefly
```

Startup runs database migrations automatically. Check balances, receipt downloads, scheduled jobs and API access. PostgreSQL major upgrades require their own export/import plan; never point an existing data directory at a different major version.

<!-- coverage:rollback -->
## Rollback

1. Close external access and stop `cron` and `firefly`.
2. Restore the previous Compose and `.env`, preserving the correct encryption key and the same database major version. Set the previous `FIREFLY_VERSION`.
3. Pull that image, run `docker compose up -d --wait database`, then `docker compose create --no-deps firefly cron`. Keep the application stopped so it cannot migrate the current database with older code.
4. Run `bash restore.sh /path/to/pre-upgrade.tar`. The safety copy preserves the current state, then the previous database and storage replace it.
5. Verify login, balances, transactions, attachments and API access before reopening the proxy. Never downgrade the image over a migrated database and assume compatibility.

<!-- coverage:removal -->
## Stop or remove

`docker compose down` retains the volumes. To erase the installation after exporting and verifying an external backup, run `docker compose down --volumes --remove-orphans`. This destroys all financial records, attachments and OAuth keys. Remove `.env` and local archives separately when they are no longer needed.

See the official [backup](https://docs.firefly-iii.org/how-to/firefly-iii/advanced/backup/) and [authentication](https://docs.firefly-iii.org/how-to/firefly-iii/advanced/authentication/) guides before changing the security model.
