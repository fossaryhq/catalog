### 1. Check the Ubuntu or Debian server

Minimum: 2 CPU, 1 GB RAM, and 5 GB of disk. 2 GB RAM is recommended — usage
grows with the number of concurrent executions and the size of their history.
You need Ubuntu 22.04+ or Debian 12+ with Docker Engine and Docker Compose
v2.24+. PostgreSQL comes up from the same Compose file; no separate install.

```bash
docker --version
docker compose version
```

### 2. Prepare the files and variables

Put `compose.yaml`, `.env.example`, `backup.sh`, `restore.sh`, and the `proxy`
directory into a dedicated directory:

```bash
mkdir -p ~/services/n8n
cd ~/services/n8n
cp .env.example .env
chmod 600 .env
```

Fill in the two mandatory secrets — do not start without them:

```bash
sed -i "s|^N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)|" .env
sed -i "s|^N8N_DB_PASSWORD=.*|N8N_DB_PASSWORD=$(openssl rand -hex 24)|" .env
```

`N8N_ENCRYPTION_KEY` encrypts the passwords and tokens of every connected
service. Never change it after the first start: with the existing database, a
new key makes the stored credentials unreadable. Keep the key in a password
manager, separately from the server.

The remaining `.env` variables:

- `N8N_VERSION` — the pinned image tag; the stable line is 2.36.x, while 2.37.x tags on Docker Hub belong to the beta channel;
- `N8N_PORT` — the local editor port, `5678` by default;
- `N8N_DB_NAME` and `N8N_DB_USER` — database name and user, changeable only before the first start;
- `N8N_PUBLIC_HOST` and `N8N_PROTOCOL` — external host name and scheme, used in the links the UI generates;
- `N8N_WEBHOOK_URL` — the full external address when publishing behind a reverse proxy;
- `N8N_SECURE_COOKIE` — whether the session cookie is sent over HTTPS and localhost only;
- `N8N_PROXY_HOPS` — the number of reverse proxies in front of n8n;
- `N8N_DIAGNOSTICS` and `N8N_VERSION_NOTIFICATIONS` — telemetry and update checks, disabled by default;
- `N8N_EXECUTIONS_MAX_AGE_HOURS` — how long the execution history is kept, two weeks by default;
- `N8N_DATA_VOLUME` and `N8N_DB_VOLUME` — the Docker volume names;
- `TZ` — the time zone, which the Schedule and Cron nodes follow.

Data lives in two volumes: `n8n-data` holds the encryption key, settings, and
binary execution data, while `n8n-database` holds the workflows, credentials,
and history. Nothing is stored in the recipe directory.

### 3. Start it on a VPS

<!-- coverage:deployment-vps -->

```bash
docker compose pull
docker compose up -d
docker compose ps
```

The first start takes longer than usual: n8n runs the database migrations. The
default port is reachable on `127.0.0.1` only, and PostgreSQL is not published
to the host at all.

### 4. Create the instance owner

```bash
ssh -L 5678:127.0.0.1:5678 user@server.example
```

Open `http://localhost:5678`, create the owner account, and store the password
in a password manager. Until the owner exists the UI is reachable without
authentication, so do not expose the port before this step.

### Local network

<!-- coverage:deployment-lan -->

Without a reverse proxy it is safer to keep the localhost bind and use an SSH
tunnel. If the editor has to be reachable from a trusted LAN, replace
`127.0.0.1` in `compose.yaml` with the server address, for example
`192.168.1.10`, and do not use `0.0.0.0`.

Over plain HTTP on a non-localhost address n8n will not send the session cookie,
and the login silently fails. For that case, in `.env`:

```bash
sed -i 's/^N8N_SECURE_COOKIE=.*/N8N_SECURE_COOKIE=false/' .env
sed -i 's|^N8N_PUBLIC_HOST=.*|N8N_PUBLIC_HOST=192.168.1.10|' .env
docker compose up -d
```

Turning `N8N_SECURE_COOKIE` off means the session cookie travels in clear text.
That is acceptable inside a trusted network only; for outside access set up
HTTPS.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

The samples live in `proxy/Caddyfile`, `proxy/nginx.conf`, and
`proxy/traefik.yaml`; replace `n8n.example.com` with your domain. Caddy obtains a
certificate automatically, the Nginx sample assumes a Certbot certificate, and
Traefik uses the `letsencrypt` resolver. For Traefik in a container, replace
`127.0.0.1` with a host gateway address the container can reach.

After publishing, set the external address — otherwise webhooks hand out
`localhost` links that external services cannot reach:

```bash
sed -i 's|^N8N_WEBHOOK_URL=.*|N8N_WEBHOOK_URL=https://n8n.example.com/|' .env
sed -i 's|^N8N_PUBLIC_HOST=.*|N8N_PUBLIC_HOST=n8n.example.com|' .env
sed -i 's|^N8N_PROTOCOL=.*|N8N_PROTOCOL=https|' .env
sed -i 's|^N8N_PROXY_HOPS=.*|N8N_PROXY_HOPS=1|' .env
docker compose up -d
```

Publishing webhooks also exposes the editor: it lives on the same port. Restrict
access by IP or with basic authentication on the proxy side if only the webhooks
need to be reachable.

### Backup

<!-- coverage:backup -->

The script stops n8n, takes a PostgreSQL dump, and archives the volume holding
the encryption key — separately they are useless:

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The archive appears in `./backups`. It contains decryptable access to every
connected service, so keep a copy off the server and encrypt it.

### Restore

<!-- coverage:restore -->

Restoring completely replaces the database and the data directory with the
chosen archive:

```bash
./restore.sh ./backups/n8n-YYYYMMDDTHHMMSSZ.tar
docker compose ps
```

Before the replacement the script creates a safety copy of the current state.
The `N8N_ENCRYPTION_KEY` value in `.env` must match the one the archive was made
with, otherwise the workflows come back but the service credentials do not.

### Update

<!-- coverage:update -->

Create a backup, read the release notes, change `N8N_VERSION` in `.env`, then
run:

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 n8n
```

Do not skip major versions: the migrations expect sequential upgrades. Stay
within the stable 2.36.x line while 2.37.x remains the beta channel.

### Rollback

<!-- coverage:rollback -->

Restore the previous `N8N_VERSION` in `.env` and run `docker compose pull` and
`docker compose up -d`. If the new version already ran its database migrations,
rolling the image back is not enough: the older n8n cannot read the new schema.
In that case restore the archive made before the update:

```bash
./restore.sh ./backups/n8n-YYYYMMDDTHHMMSSZ.tar
```

This is why a backup before every update is mandatory: it is the only thing that
makes a rollback possible.

### Removal

<!-- coverage:removal -->

Keep the data: `docker compose down`. Remove the containers and all data
irreversibly:

```bash
docker compose down
docker volume rm n8n-data n8n-database
rm -rf ~/services/n8n
```

Disable the webhooks in the external services before removal, or they will keep
hitting an address that no longer exists.

Sources: [Docker installation](https://docs.n8n.io/hosting/installation/docker/),
[environment variables](https://docs.n8n.io/hosting/configuration/environment-variables/),
and [updating](https://docs.n8n.io/hosting/installation/updating/).
