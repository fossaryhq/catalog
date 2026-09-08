### 1. Check the Ubuntu or Debian server

Use Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. Allocate
at least 2 CPUs, 2 GB RAM, and 5 GB disk; 4 GB RAM plus dedicated room for web
archives is recommended. The official image declares amd64 and arm64.

```bash
docker --version
docker compose version
```

### 2. Prepare the recipe and independent secrets

```bash
mkdir -p ~/services/linkwarden
cd ~/services/linkwarden
cp .env.example .env
chmod 600 .env
nextauth_secret="$(openssl rand -hex 32)"
postgres_password="$(openssl rand -hex 32)"
meili_key="$(openssl rand -hex 32)"
sed -i "s|^NEXTAUTH_SECRET=.*|NEXTAUTH_SECRET=$nextauth_secret|" .env
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$postgres_password|" .env
sed -i "s|^MEILI_MASTER_KEY=.*|MEILI_MASTER_KEY=$meili_key|" .env
unset nextauth_secret postgres_password meili_key
```

All three secrets are required, must differ, and must remain stable after the
first start. A hexadecimal value is safe inside the PostgreSQL URL. Store the
secrets in a password manager.

Every `.env` variable:

- `LINKWARDEN_PORT` is the local web port, default `3000`;
- `LINKWARDEN_URL` is the exact public application URL without a trailing `/`;
- `LINKWARDEN_USER_CONTENT_URL` is a separate HTTPS origin for preserved HTML, preferably on another registrable domain and without shared cookies;
- `NEXT_PUBLIC_DISABLE_REGISTRATION` stays `false` only while creating the first account and must then become `true`;
- `NEXTAUTH_SECRET` is the persistent NextAuth session and token secret;
- `POSTGRES_PASSWORD` is an independent URL-safe PostgreSQL password;
- `MEILI_MASTER_KEY` is an independent Meilisearch master key;
- `POSTGRES_DB` and `POSTGRES_USER` are the database and role names, changed only before the first start;
- `LINKWARDEN_TIME_ZONE` is an IANA time zone;
- `LINKWARDEN_DATA_VOLUME`, `LINKWARDEN_DB_VOLUME`, and `LINKWARDEN_MEILI_VOLUME` name archive, PostgreSQL, and search-index volumes;
- `LINKWARDEN_BACKUP_DIR` selects the host backup directory.

The recipe derives `NEXTAUTH_URL` as `${LINKWARDEN_URL}/api/v1/auth`, while
`BASE_URL` equals `LINKWARDEN_URL`. Do not omit `/api/v1/auth` from the auth URL.

### 3. Start and close registration

```bash
docker compose config
docker compose pull
docker compose up -d --wait --wait-timeout 900
docker compose ps
curl -I http://127.0.0.1:3000/
```

Open `LINKWARDEN_URL`, create the first account, immediately set
`NEXT_PUBLIC_DISABLE_REGISTRATION=true`, and apply it:

```bash
docker compose up -d --force-recreate linkwarden
```

Use a private window to confirm sign-up is unavailable. Do not expose the
service publicly before this step.

### VPS deployment

<!-- coverage:deployment-vps -->

Keep `127.0.0.1:${LINKWARDEN_PORT}:3000`; only an HTTPS proxy on the host can
reach the app. PostgreSQL and Meilisearch have no published ports. Allow only
SSH, HTTP, and HTTPS through the firewall. Create DNS for both the application
and user-content origins before the first start.

### Trusted LAN access

<!-- coverage:deployment-lan -->

Prefer `ssh -L 3000:127.0.0.1:3000 user@server` and use
`LINKWARDEN_URL=http://localhost:3000` for that route. For permanent LAN access,
replace the localhost bind with one specific private IP, use a matching URL, and
restrict the port with a firewall. Do not use `0.0.0.0` without network controls.
Without HTTPS, preserved-content origin isolation is weaker, so this mode is for
a trusted network only.

### Domain, HTTPS, and preserved HTML

<!-- coverage:deployment-domain-https -->

Set `LINKWARDEN_URL=https://links.example.com` and a separate
`LINKWARDEN_USER_CONTENT_URL=https://saved.example.net`, then replace both hosts
in the Caddy, Nginx, or Traefik example. For stronger isolation, use another
registrable domain rather than an application subdomain, and never set shared
parent-domain cookies. The certificate must cover both hosts; replace the Nginx
sample paths with a suitable SAN or separate certificates. The proxy must
support WebSockets and preserve `Host` and `X-Forwarded-Proto`.

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops Linkwarden and Meilisearch, keeps PostgreSQL available for a
native `pg_dump`, archives `/data/data`, `/meili_data`, `.env`, and Compose, then
restarts the services. A UI JSON export is not a complete backup: it omits
preserved pages, documents, and extracted text. The archive holds secrets and
user content; encrypt it, copy it off the server, and test restores regularly.

### Restore

<!-- coverage:restore -->

Restore irreversibly replaces application data, PostgreSQL, and the Meilisearch
index. Use the same Linkwarden, PostgreSQL, and Meilisearch versions with the
active `.env`:

```bash
./restore.sh ./backups/linkwarden-YYYYMMDDTHHMMSSZ.tar
curl -I http://127.0.0.1:3000/
```

The script first backs up the state being replaced, recreates all three volumes,
restores the dump, and starts the stack. The archived `configuration.env` is
retained for comparison only. This procedure has not passed a practical restore
test; test it on a separate server first.

### Update Linkwarden

<!-- coverage:update -->

Create a backup, read release notes, and replace the exact
`ghcr.io/linkwarden/linkwarden:v2.16.2` tag with a reviewed version. Never use
`latest`, and do not update PostgreSQL or Meilisearch at the same time:

```bash
docker compose pull
docker compose up -d --wait --wait-timeout 900
curl -I http://127.0.0.1:3000/
docker compose logs --tail=200 linkwarden postgres meilisearch
```

Application database migrations run at startup. A PostgreSQL major upgrade
requires a new empty volume and native-dump restore. A Meilisearch major change
requires its upgrade guide; retain the old volume until search is verified.

### Rollback

<!-- coverage:rollback -->

Never run an older Linkwarden over a database after newer migrations. Restore
all previous exact tags and the complete pre-update archive with `restore.sh`.
After a failed PostgreSQL or Meilisearch change, attach the old image only to its
preserved old volume, or restore a compatible dump/backup into an empty volume.

### Stop and remove

<!-- coverage:removal -->

`docker compose down` preserves data. After verifying an off-server backup,
remove everything irreversibly:

```bash
docker compose down
docker volume rm linkwarden-data linkwarden-postgres linkwarden-meilisearch
rm -rf ~/services/linkwarden
```

Substitute actual names when volume variables differ.

Sources: [self-hosting setup](https://docs.linkwarden.app/self-hosting/setup),
[environment variables](https://docs.linkwarden.app/self-hosting/environment-variables),
[user-content domain](https://docs.linkwarden.app/self-hosting/user-content-domain),
[release v2.16.2](https://github.com/linkwarden/linkwarden/releases/tag/v2.16.2), and
[PostgreSQL upgrades](https://www.postgresql.org/docs/16/upgrading.html).
