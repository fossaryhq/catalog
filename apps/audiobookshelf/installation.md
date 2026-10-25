<!-- coverage:os -->
# Install Audiobookshelf

Requires Docker Engine, Compose >=2.24, 1 CPU, at least 512 MB RAM (1 GB recommended), and enough disk for all media and backups. The image publishes amd64 and arm64; this recipe was tested on amd64.

```sh
cp .env.example .env
chmod 600 .env
openssl rand -hex 24
```

Put the generated password in `AUDIOBOOKSHELF_ADMIN_PASSWORD`. Then start and initialize locally **before enabling a public reverse proxy**:

```sh
docker compose up -d --wait
docker compose run --rm -T bootstrap
docker compose ps
```

Open `http://127.0.0.1:13378` and sign in as `admin` with the password from `.env`. For a remote host use an SSH tunnel: `ssh -L 13378:127.0.0.1:13378 user@server`. The unauthenticated first-user setup is closed only after bootstrap succeeds. Re-running bootstrap keeps existing credentials; changing `.env` never resets an account password. Change passwords in the application.

## Environment

- `AUDIOBOOKSHELF_VERSION`: fixed official image version, initially `2.37.2`.
- `AUDIOBOOKSHELF_PORT`: loopback HTTP port, initially `13378`.
- `AUDIOBOOKSHELF_ADMIN_PASSWORD`: unique initial admin password, at least 16 characters, no `CHANGE_ME` placeholder.
- `AUDIOBOOKSHELF_DATA_VOLUME`: named volume holding **all** persistent data; use a unique name for each installation.
- `TZ`: IANA time zone, initially `Etc/UTC`.
- `AUDIOBOOKSHELF_BACKUP_DIR`: optional backup output directory; defaults to `./backups`.

## Add your media

Create a book library in the administration interface with folder `/data/audiobooks`, and optionally a podcast library at `/data/podcasts`. Store each book in its own author/title folder. For example, copy a local folder through the service container (which writes as UID 1000):

```sh
docker compose cp './My Book' audiobookshelf:/data/audiobooks/
docker compose run --rm permissions
```

Scan the library. Use only media you have permission to host. Media outside `/data` is not backed up by this recipe. Create regular listener accounts and select their accessible libraries; do not share the root account.

<!-- coverage:deployment-domain-https -->
## HTTPS

After bootstrap succeeds, choose `proxy/Caddyfile` or `proxy/nginx.conf`, set your domain, and adjust the upstream port if changed. These examples assume a proxy on the same host. A containerized proxy needs a deliberately configured network route; its `127.0.0.1` is its own container. Keep port 13378 private. OIDC and RSS sharing are optional upstream features and are not enabled here.

<!-- coverage:backup -->
## Backup and recovery

```sh
./backup.sh
./restore.sh backups/audiobookshelf-TIMESTAMP.tar
```

Backup stops the app, archives the **whole volume** plus `.env` and Compose, and restores its prior running/stopped state. Encrypt the archive and copy it off-server. It can be as large as your media collection. Host tools needed: Bash, tar, gzip and Docker; smoke additionally uses Python 3 and OpenSSL.

<!-- coverage:restore -->
## Restore

Restore accepts only your trusted archives, verifies the database and all media directories before mutation, creates a safety backup, replaces data, and waits for health. Start the recipe once on a fresh destination before restore. Saved `.env` is never executed automatically: compare it privately and use the matching image version. Restored account passwords and JWT key take precedence over bootstrap values. Check a book plays and listening state is present after recovery.

<!-- coverage:update -->
## Updates

Take an off-server backup, review release notes, set a tested explicit version in `.env`, then run `docker compose pull && docker compose up -d --wait`. Verify login and playback. To roll back a database migration, restore the pre-upgrade full archive with its matching version; changing only an image tag can be insufficient.

<!-- coverage:deployment-vps -->
## VPS

Keep HTTP on loopback and block it in the firewall. Use an SSH tunnel and bootstrap first, then enable the domain and HTTPS.

<!-- coverage:deployment-lan -->
## LAN / VPN

Use an SSH tunnel or a protected VPN proxy for a home server. Do not expose an uninitialized instance to an untrusted network.

<!-- coverage:proxy-caddy -->
## Caddy

After bootstrap, configure `proxy/Caddyfile`, your domain and DNS. Caddy obtains the TLS certificate.

<!-- coverage:proxy-nginx -->
## Nginx

After bootstrap, configure `proxy/nginx.conf`, your domain and valid TLS certificates. The sample supports WebSocket and long streams.

<!-- coverage:proxy-traefik -->
## Traefik

After bootstrap, load `proxy/traefik.yaml` through a host-based Traefik file provider. It needs websecure and letsencrypt. Configure a separate route for a containerized proxy.

<!-- coverage:data -->
## Data / Данные

One named volume holds config, metadata, audiobooks and podcasts. Retain it during ordinary updates. Data must be writable by UID/GID 1000.

<!-- coverage:rollback -->
## Rollback / Откат

Save the current state, then restore the full pre-upgrade archive with its matching image version. Do not run an old version against a migrated database.

<!-- coverage:removal -->
## Removal / Удаление

`docker compose down` keeps the volume. After verifying an off-server backup, `docker compose down --volumes` permanently deletes the media library, accounts and progress.
