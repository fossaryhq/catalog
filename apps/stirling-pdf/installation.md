### 1. Check the Ubuntu or Debian server

Use Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. Allocate
at least 2 CPUs, 2 GB RAM, and 10 GB disk; 4 GB RAM is recommended. OCR,
LibreOffice, and large PDFs can briefly consume more CPU, RAM, and temporary
space.

```bash
docker --version
docker compose version
```

### 2. Prepare the recipe and required credentials

```bash
mkdir -p ~/services/stirling-pdf
cd ~/services/stirling-pdf
cp .env.example .env
chmod 600 .env
mkdir -p data/{configs,customFiles,pipeline,tessdata}
sed -i "s|^STIRLING_PDF_INITIAL_PASSWORD=.*|STIRLING_PDF_INITIAL_PASSWORD=$(openssl rand -base64 36 | tr -d '\n')|" .env
```

Before the **first** start, replace `STIRLING_PDF_INITIAL_USERNAME` and save the
generated password in a secret manager. Initial-login variables are consumed
only while H2 is created; editing `.env` later does not reset the password. This
recipe never uses the upstream `admin/stirling` default.

Every `.env` variable:

- `STIRLING_PDF_PORT` is the local web port, normally `8080`;
- `STIRLING_PDF_URL` is the exact public origin with a scheme, no trailing `/`, and no path; it becomes the frontend URL, backend URL, and sole CORS origin;
- `STIRLING_PDF_DATA_PATH` is the root of four bind-mounted directories;
- `STIRLING_PDF_INITIAL_USERNAME` and `STIRLING_PDF_INITIAL_PASSWORD` are required non-default first-administrator credentials;
- `STIRLING_PDF_DEFAULT_LOCALE` is the UI locale, default `en-GB`; `ru-RU` and the other supported locales work too;
- `STIRLING_PDF_UPLOAD_LIMIT_MB` is a defensive file and request limit from 1 to 999 MB;
- `STIRLING_PDF_BACKUP_DIR` selects the host archive directory.

`configs` holds settings, users, and the
`stirling-pdf-DB-<schema-version>.mv.db` H2 file; `customFiles` holds branding
and signatures; `pipeline` holds automations and watched folders; `tessdata`
holds OCR languages. Read logs with `docker compose logs`: persistent `/logs`
is not needed for recovery and is deliberately omitted.

### 3. Start and change the password

```bash
docker compose config
docker compose pull
docker compose up -d --wait
curl --fail http://127.0.0.1:8080/api/v1/info/status
```

Open `STIRLING_PDF_URL`, sign in with the initial credentials, and immediately
change the password in account settings. Authentication is enabled. Analytics,
PostHog, Scarf, Google visibility, and URL-to-PDF are disabled; the health
endpoint remains reachable without login. Do not expose the service until login
has been verified.

### VPS deployment

<!-- coverage:deployment-vps -->

Keep `127.0.0.1:${STIRLING_PDF_PORT}:8080`, allow only SSH, HTTP, and HTTPS in
the firewall, and expose the app through a proxy on the same host. Set the real
HTTPS origin in `STIRLING_PDF_URL`, DNS, and proxy before first startup. H2 fits
this free single-container recipe; do not add external PostgreSQL as an
"improvement" without an applicable paid licence.

### Trusted LAN access

<!-- coverage:deployment-lan -->

Prefer a VPN or `ssh -L 8080:127.0.0.1:8080 user@server`; temporarily set
`STIRLING_PDF_URL=http://localhost:8080` for that tunnel. For permanent LAN
access, replace only `127.0.0.1` in Compose with a specific private address, set
the matching origin, and restrict the port by firewall. Do not use `0.0.0.0`
without filtering.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Set `STIRLING_PDF_URL=https://pdf.example.com` without a path or trailing slash,
replace the domain in `proxy/Caddyfile`, `proxy/nginx.conf`, or
`proxy/traefik.yaml`, and recreate the container. Caddy obtains a certificate,
Nginx expects Certbot, and Traefik uses the `letsencrypt` resolver. Preserve
`Host`, `X-Forwarded-Proto`, and client addresses, and keep the proxy upload
limit aligned with `STIRLING_PDF_UPLOAD_LIMIT_MB`. A containerized proxy cannot
reach host localhost; use a reachable host gateway or shared Docker network.

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh smoke-test.sh
./backup.sh
```

The script stops Stirling PDF so H2 cannot change while it archives `configs`,
`customFiles`, `pipeline`, and `tessdata` together, then restarts the container.
The archive contains H2 users and sensitive settings: encrypt it, copy it off
the server, and test restores regularly. Input and temporary PDFs are normally
deleted and are not backed up. Copy any separately allowed pipeline directories
outside `STIRLING_PDF_DATA_PATH` yourself.

### Restore

<!-- coverage:restore -->

Restore irreversibly replaces all four directories. Put the **same 2.14.3
version** in Compose, retain the active `.env`, verify free space, and run:

```bash
./restore.sh ./backups/stirling-pdf-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
curl --fail http://127.0.0.1:8080/api/v1/info/status
```

The script saves the replaced state in an emergency archive, restores the
stopped snapshot, and waits for health. The procedure has `restore_tested:
false`; test a copy on another server first and verify login, settings, custom
files, and pipelines.

### Update

<!-- coverage:update -->

Back up first and read the new release notes, migration guide, and licence.
Replace only the exact `stirlingtools/stirling-pdf:2.14.3` tag with a reviewed
semantic version, never `latest`, then run:

```bash
docker compose pull
docker compose up -d --wait
docker compose logs --tail=200 stirling-pdf
curl --fail http://127.0.0.1:8080/api/v1/info/status
```

Startup may migrate H2 and create a file with a new schema version. Review major
releases, persistent-path changes, and the User License separately.

### Rollback

<!-- coverage:rollback -->

Never run an old image over already migrated H2. Stop the container, restore the
old exact tag, and restore the complete **pre-update** archive with `restore.sh`.
H2 has no supported downgrade: migration rollback means returning synchronized
`configs`, `customFiles`, `pipeline`, and `tessdata`. Without a backup, preserve
the current state and contact upstream instead of renaming H2 files manually.

### Stop and remove

<!-- coverage:removal -->

`docker compose down` preserves bind-mounted data. After verifying an external
backup, remove everything irreversibly:

```bash
docker compose down
rm -rf ./data ./backups .env
```

Sources: [Docker installation](https://docs.stirlingpdf.com/Installation/Docker%20Install/),
[configuration](https://docs.stirlingpdf.com/Configuration/),
[production, health, and backup](https://docs.stirlingpdf.com/Production-Deployment-Guide/),
[analytics](https://docs.stirlingpdf.com/analytics-telemetry/),
[modes and licensing](https://docs.stirlingpdf.com/Modes%20and%20Licensing/), and
the [2.14.3 licence](https://github.com/Stirling-Tools/Stirling-PDF/blob/v2.14.3/LICENSE).
