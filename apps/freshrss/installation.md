### 1. Check the Ubuntu or Debian server

Use Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. Allocate
at least 1 CPU, 512 MB RAM, and 2 GB disk; 1 GB RAM plus room for article history
and backups is recommended. The official image declares amd64, arm64, and armv7.

```bash
docker --version
docker compose version
```

### 2. Prepare the recipe and independent secrets

```bash
mkdir -p ~/services/freshrss
cd ~/services/freshrss
cp .env.example .env
chmod 600 .env
login_password="$(openssl rand -hex 24)"
api_password="$(openssl rand -hex 24)"
db_password="$(openssl rand -hex 24)"
sed -i "s|^FRESHRSS_ADMIN_PASSWORD=.*|FRESHRSS_ADMIN_PASSWORD=$login_password|" .env
sed -i "s|^FRESHRSS_ADMIN_API_PASSWORD=.*|FRESHRSS_ADMIN_API_PASSWORD=$api_password|" .env
sed -i "s|^FRESHRSS_DB_PASSWORD=.*|FRESHRSS_DB_PASSWORD=$db_password|" .env
unset login_password api_password db_password
```

These secrets contain letters and digits only. The 1.29.1 entrypoint evaluates
first-run option strings through shell `eval`, so spaces and shell metacharacters
are unsafe here. All three values must differ. Store them in a password manager:
API clients use the API password, not the web login password.

Every `.env` variable:

- `FRESHRSS_PORT` is the local web port, default `8080`;
- `FRESHRSS_BASE_URL` is the exact public HTTPS URL without a trailing `/`; a dedicated subdomain is more reliable than a subpath;
- `FRESHRSS_ADMIN_USER` is the ASCII-alphanumeric initial administrator login, distinct from secrets and changeable only before initialization;
- `FRESHRSS_ADMIN_PASSWORD` and `FRESHRSS_ADMIN_API_PASSWORD` are independent alphanumeric form-auth and Google Reader/Fever API passwords;
- `FRESHRSS_ADMIN_EMAIL` is the initial administrator email;
- `FRESHRSS_DB_PASSWORD` is the required independent PostgreSQL password;
- `FRESHRSS_DB_NAME` and `FRESHRSS_DB_USER` are the database and role names, changed only before the first start;
- `FRESHRSS_TIME_ZONE` is an IANA time zone;
- `FRESHRSS_CRON_MIN` selects built-in cron minutes; `13,43` refreshes twice per hour without joining the minute-zero spike;
- `FRESHRSS_TRUSTED_PROXY` controls trust in forwarded client-IP and external-auth headers; the safe default is `0`, never a broad network;
- `FRESHRSS_DATA_VOLUME`, `FRESHRSS_EXTENSIONS_VOLUME`, and `FRESHRSS_DB_VOLUME` name persistent volumes;
- `FRESHRSS_BACKUP_DIR` selects the host backup directory.

`freshrss-data` holds configuration, users, and service files;
`freshrss-extensions` holds third-party extensions; `freshrss-database` holds
PostgreSQL.

### 3. Run deterministic initialization

```bash
docker compose config
docker compose pull
docker compose up -d --wait
docker compose exec freshrss cli/health.php
docker compose exec freshrss cli/list-users.php
```

On an empty data volume, `FRESHRSS_INSTALL` creates a production PostgreSQL
configuration with `form` auth, anonymous access disabled, API enabled, English
as the interface language, and the exact base URL. `FRESHRSS_USER` creates the administrator.
Changing these variables after initialization does not modify the existing user.

### VPS deployment

<!-- coverage:deployment-vps -->

Keep `127.0.0.1:${FRESHRSS_PORT}:80`; only an HTTPS proxy on the host can reach
web. PostgreSQL has no published port. Allow only SSH, HTTP, and HTTPS through
the firewall. Configure DNS and replace `FRESHRSS_BASE_URL` and one proxy example
before starting. Do not invite untrusted users: they can make the server fetch
URLs from internal networks.

### Trusted LAN access

<!-- coverage:deployment-lan -->

Prefer `ssh -L 8080:127.0.0.1:8080 user@server`; before the first start, use
`FRESHRSS_BASE_URL=http://localhost:8080` for that route. For permanent LAN
access, replace the localhost bind with one specific private IP, use a matching
base URL, and restrict the port with a firewall. Do not use `0.0.0.0` without
network controls.

### Domain, HTTPS, and API clients

<!-- coverage:deployment-domain-https -->

Use a dedicated host such as `https://rss.example.com` without a trailing `/` in
both `.env` and Caddy, Nginx, or Traefik. Caddy obtains a certificate, Nginx
expects Certbot files, and Traefik uses the `letsencrypt` resolver. The proxy
keeps `Host` and forwards `X-Forwarded-Proto` and `Authorization`, required by
some Google Reader API clients. FreshRSS does not require WebSockets, so upgrade
headers are deliberately absent. Never replace or remove FreshRSS's CSP;
upstream explicitly warns proxies not to override it.

`FRESHRSS_TRUSTED_PROXY=0` does not trust forwarded client IP or external-auth
headers. Form auth and the API work with an exact `base_url` without a broad
trusted range. If external auth is genuinely needed, list only the exact IP/CIDR
of the final secured proxy; an extra trusted address can spoof a user.

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops FreshRSS and its built-in cron, keeps PostgreSQL available for
native `pg_dump`, archives complete data and extensions plus `.env` and Compose,
then restarts the app. This is a consistent full backup. OPML is insufficient:
it omits articles, users, feed credentials, refresh frequency, user agents, and
XPath scraping rules. Encrypt the archive, copy it off the server, and test
restores regularly.

### Restore

<!-- coverage:restore -->

Restore irreversibly replaces data, extensions, and PostgreSQL. Use the same
FreshRSS version and the active `.env`, then run:

```bash
./restore.sh ./backups/freshrss-YYYYMMDDTHHMMSSZ.tar
docker compose exec freshrss cli/health.php
```

The script first backs up the state being replaced, recreates all three volumes,
restores the native dump, and starts FreshRSS. The archived `configuration.env`
is retained for comparison only. This procedure has not passed a practical
restore test; test it on a separate server first.

### Update FreshRSS

<!-- coverage:update -->

Create a backup and read release notes. Replace the exact
`freshrss/freshrss:1.29.1` tag with a reviewed version, never `latest`, then run:

```bash
docker compose pull
docker compose up -d --wait
docker compose exec freshrss cli/health.php
docker compose logs --tail=200 freshrss
```

Application migrations run at startup. Do not update FreshRSS and PostgreSQL at
the same time, so rollback remains unambiguous.

### PostgreSQL major update

`postgres:18-alpine` is pinned independently. A major change requires a new data
volume; old and new server majors must never share a cluster directory. Stop
FreshRSS, keep a native `pg_dump` and complete data/extensions backup, create a
new volume with the new image, and restore the dump. Upstream also offers
`cli/db-backup.php` and `cli/db-restore.php` for portable per-user SQLite exports.
Keep the old volume until the new database is verified.

### Rollback

<!-- coverage:rollback -->

Never run an older FreshRSS over migrated data. Restore the previous exact
FreshRSS and PostgreSQL tags and the complete pre-update archive with
`restore.sh`. After a failed PostgreSQL major change, attach the old image only
to its preserved old volume, or restore its dump into an empty cluster of the
same major.

### Stop and remove

<!-- coverage:removal -->

`docker compose down` preserves data. After verifying an off-server backup,
remove everything irreversibly:

```bash
docker compose down
docker volume rm freshrss-data freshrss-extensions freshrss-database
rm -rf ~/services/freshrss
```

Substitute actual names when volume variables differ.

Sources: [Docker and first run](https://github.com/FreshRSS/FreshRSS/blob/1.29.1/Docker/README.md),
[backup and OPML](https://freshrss.github.io/FreshRSS/en/admins/05_Backup.html),
[access control and SSRF](https://freshrss.github.io/FreshRSS/en/admins/09_AccessControl.html),
[server CSP](https://freshrss.github.io/FreshRSS/en/admins/10_ServerConfig.html), and
[PostgreSQL upgrades](https://www.postgresql.org/docs/18/upgrading.html).
