### 1. Check the Ubuntu or Debian server

Use Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. Allocate
at least 2 CPUs, 2 GB RAM, and 10 GB disk; 4 GB RAM is recommended. OCR briefly
loads the CPU and needs extra room for originals, PDF/A renditions, and
thumbnails.

```bash
docker --version
docker compose version
```

### 2. Prepare the recipe and secrets

```bash
mkdir -p ~/services/paperless-ngx
cd ~/services/paperless-ngx
cp .env.example .env
chmod 600 .env
sed -i "s|^PAPERLESS_SECRET_KEY=.*|PAPERLESS_SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_urlsafe(64))')|" .env
sed -i "s|^PAPERLESS_DB_PASSWORD=.*|PAPERLESS_DB_PASSWORD=$(openssl rand -hex 32)|" .env
```

Never publish `.env`. `PAPERLESS_SECRET_KEY` signs sessions and sensitive data;
`PAPERLESS_DB_PASSWORD` protects PostgreSQL. Both are required. Store them in a
secret manager and do not change them when restoring an existing archive.

Every `.env` variable:

- `PAPERLESS_PORT` is the local web port, default `8000`;
- `PAPERLESS_URL` is the sole public origin with `https`, no trailing `/`, and no path; it configures allowed hosts, CORS, and CSRF origins;
- `PAPERLESS_SECRET_KEY` is the required random signing key;
- `PAPERLESS_DB_PASSWORD` is the required random database password;
- `PAPERLESS_DB_NAME` and `PAPERLESS_DB_USER` name the database and role and should change only before first start;
- `PAPERLESS_TIME_ZONE` is an IANA time zone for dates and background tasks;
- `PAPERLESS_OCR_LANGUAGE` is what to recognize in a document, default `eng`; use `rus+eng` for two;
- `PAPERLESS_OCR_LANGUAGES` is which tesseract packs to install at start, so add `rus` here before naming it above;
- the `PAPERLESS_*_VOLUME` variables name data, media, export, consume, PostgreSQL, and Valkey volumes;
- `PAPERLESS_BACKUP_DIR` selects the final archive directory on the host.

`paperless-data` holds the index, classifier, and auxiliary state;
`paperless-media` stores originals, archive renditions, and thumbnails;
`paperless-export` stores exporter output; `paperless-consume` holds incoming
files; the remaining volumes store the PostgreSQL cluster and Valkey state. The
recipe encrypts none of them.

### 3. Start and create an administrator

```bash
docker compose config
docker compose pull
docker compose up -d --wait
curl -I --fail http://127.0.0.1:8000/
docker compose exec webserver createsuperuser
```

The last command asks for username, email, and password interactively. The
password enters neither `.env` nor shell history and does not remain in the
container environment. Self-registration is disabled. Do not expose the service
before creating the administrator. Inspect it with `docker compose ps` and
`docker compose logs --tail=100 webserver`.

Documents reach the archive two ways: **Upload documents** in the web interface,
and the consume folder the container watches. This recipe keeps that folder in
the named volume `paperless-consume`, so nothing on the host writes into it
directly — which is also what lets `backup.sh` archive it. A scanner or a
synchronized directory needs a bind mount instead of the volume in
`compose.yaml`:

```yaml
    volumes:
      - /srv/paperless/consume:/usr/src/paperless/consume
```

Create that directory for the container user first — it runs as uid 1000:
`sudo install -d -o 1000 -g 1000 /srv/paperless/consume`. From then on the
consume folder is outside the backup: `backup.sh` archives the volume named in
`.env`, not a host path, so add the directory to the host backup instead.

### VPS deployment

<!-- coverage:deployment-vps -->

Keep `127.0.0.1:${PAPERLESS_PORT}:8000`; only an HTTPS reverse proxy on the host
should reach web. PostgreSQL and Valkey have no published ports. Allow only SSH,
HTTP, and HTTPS through the firewall. Before the first login, replace the domain
in `PAPERLESS_URL` and the proxy example, then configure DNS and TLS.

### Trusted LAN access

<!-- coverage:deployment-lan -->

Without a domain, keep the localhost binding and use
`ssh -L 8000:127.0.0.1:8000 user@server`; set
`PAPERLESS_URL=http://localhost:8000` and recreate webserver for that temporary
access. For permanent LAN access, replace `127.0.0.1` in `compose.yaml` with a
specific private address such as `192.168.1.10`, set
`PAPERLESS_URL=http://192.168.1.10:8000`, and restrict the port by firewall. Do
not use `0.0.0.0` without network controls.

### Domain, HTTPS, and WebSockets

<!-- coverage:deployment-domain-https -->

Set `PAPERLESS_URL=https://paperless.example.com` with no trailing slash. A path
such as `/paperless` is invalid in this setting. Replace the domain in
`proxy/Caddyfile`, `proxy/nginx.conf`, or `proxy/traefik.yaml`. Caddy obtains a
certificate, Nginx expects Certbot files, and Traefik uses the `letsencrypt`
resolver. Then run:

```bash
docker compose up -d --force-recreate webserver
```

The proxy must preserve `Host`, send `X-Forwarded-Proto: https`, and forward the
client address. Background processing status uses `/ws/status/` WebSockets:
Caddy and Traefik handle upgrades automatically, while Nginx is configured
explicitly. For a containerized proxy, `127.0.0.1` refers to that proxy; use a
reachable host gateway instead.

### Backup

<!-- coverage:backup -->

Wait for tasks to finish and ensure `consume` is empty, then run:

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script runs the official `document_exporter` and packages its export,
unconsumed files, `.env`, and Compose into one tar. The export contains documents,
thumbnails, metadata, users, and an exact data snapshot, but **does not contain
API tokens**; issue new tokens after restore. Changes started during export may
not belong to one consistent snapshot, so do not ingest documents or edit
metadata during the operation. The archive contains every document and the
secrets in `.env`, so the script writes it `0600` inside a `0700` directory;
keep those permissions when you copy it, encrypt it, keep an off-server copy,
and test restores.

### Restore

<!-- coverage:restore -->

Import irreversibly replaces all six volumes. It is supported only into a
completely empty installation of the **same Paperless-ngx version**, with the
same path settings. Verify tag `3.1.2`, free space, and the active `.env`, then:

```bash
./restore.sh ./backups/paperless-ngx-YYYYMMDDTHHMMSSZ.tar
docker compose ps
docker compose exec webserver document_sanity_checker
```

The script first exports the state about to be replaced, removes the volumes,
starts an empty installation, and runs `document_importer`. The archived
`configuration.env` remains a reference for manual comparison and does not
replace active `.env`.

The round trip is part of `smoke-test.sh`, so every scheduled run of this recipe
consumes a page, backs up, deletes the document, restores, and checks that the
document and its recognized text came back, `document_sanity_checker` included.
What that does not cover is the size of your own archive or an import into a
different Paperless-ngx version, so run a restore on a separate server once
before you rely on it. API tokens are not part of the export: every one of them
stops working after the import and has to be issued again. After restoring, sign
in and check the documents, tags, correspondents, and saved views — a healthy
container proves the service started, not that the archive came back.

### Update Paperless-ngx

<!-- coverage:update -->

Wait for tasks, back up, and read the release notes and migration instructions.
Replace only the exact `paperlessngx/paperless-ngx:3.1.2` tag with a reviewed
version; never use `latest`. Then run:

```bash
docker compose pull
docker compose up -d --wait
docker compose logs --tail=200 webserver
docker compose exec webserver document_sanity_checker
```

Startup applies migrations automatically. Do not update Paperless, PostgreSQL,
and Valkey together; separate changes keep failures and rollback unambiguous.

### PostgreSQL major update

`postgres:18-alpine` is pinned independently. Changing major is not a normal
`docker compose pull`: data directory formats can be incompatible. Follow the
official PostgreSQL `pg_upgrade` or dump/restore procedure, or use
`document_exporter --data-only` and importer with a new empty database. Make and
verify a full backup first; do not change paths or remove the old volume before
verifying the new database.

### Rollback

<!-- coverage:rollback -->

Never run an older image over a database after migrations. Restore the previous
exact tag and the complete pre-update export through `restore.sh`; this rolls
back database, documents, and index together. For a failed PostgreSQL major
update, restore the old tag and old volume. Never attach an old server to a new
major's data directory.

### Stop and remove

<!-- coverage:removal -->

`docker compose down` preserves data. After verifying an external backup, remove
everything irreversibly:

```bash
docker compose down
docker volume rm paperless-data paperless-media paperless-export paperless-consume paperless-database paperless-broker
rm -rf ~/services/paperless-ngx
```

Substitute the actual names when volume variables differ in `.env`.

Sources: [configuration](https://github.com/paperless-ngx/paperless-ngx/blob/v3.1.2/docs/configuration.md),
[backup, exporter/importer, and update](https://github.com/paperless-ngx/paperless-ngx/blob/v3.1.2/docs/administration.md),
[release 3.1.2](https://github.com/paperless-ngx/paperless-ngx/releases/tag/v3.1.2), and
[PostgreSQL major upgrades](https://www.postgresql.org/docs/18/upgrading.html).
