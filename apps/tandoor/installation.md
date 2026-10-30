# Install and maintain Tandoor

<!-- coverage:linux -->
## Ubuntu and Debian

Use Ubuntu 24.04/26.04 LTS or Debian 12/13 with Docker Engine and Compose v2.24 or newer, installed from [Docker's instructions](https://docs.docker.com/engine/install/). Run commands in this recipe directory. Install `openssl`; Python 3 and curl are needed for the smoke test. Docker access grants administrative control of the host.

```bash
cp .env.example .env
chmod 600 .env
openssl rand -hex 32  # TANDOOR_SECRET_KEY
openssl rand -hex 24  # TANDOOR_DB_PASSWORD
```

Paste different generated values into `.env`. The web entrypoint rejects template secrets and a secret key shorter than 50 characters before starting HTTP. The owner password is created through the native setup form. Keep the port on loopback until that owner exists.

```bash
docker compose --env-file .env config --quiet
docker compose --env-file .env pull
docker compose --env-file .env up -d --wait --wait-timeout 600
docker compose ps --all
```

<!-- coverage:deployment-vps -->
## VPS and first owner

Leave the public proxy closed. Open a tunnel from your computer:

```bash
ssh -L 8089:127.0.0.1:8089 user@server
```

Visit `http://localhost:8089/setup/` and create the owner with a unique password, then use `http://localhost:8089/account/login/`. Setup creates the initial space and a placeholder email address; configure SMTP before verifying a real address or relying on email password recovery. Public signup stays disabled. Do not revisit `/setup/`: upstream 2.7.2 has a known redirect error there after a user exists. Enable a firewall, operating-system updates and encrypted off-server backups before opening HTTPS.

<!-- coverage:deployment-lan -->
## Trusted LAN or VPN

Bootstrap over the tunnel first. Then replace `127.0.0.1` in the web port mapping with the server's private address. Add that address to `TANDOOR_ALLOWED_HOSTS`, and set `TANDOOR_CSRF_TRUSTED_ORIGINS` to its exact origin, for example `http://192.168.1.10:8089`. Recreate the services and restrict access to trusted clients or a VPN. Plain HTTP still carries credentials and household data unencrypted.

<!-- coverage:deployment-domain-https -->
## Domain and HTTPS

Point `recipes.example.com` at the server. Keep the app on loopback, set `TANDOOR_ALLOWED_HOSTS=localhost,127.0.0.1,recipes.example.com` and `TANDOOR_CSRF_TRUSTED_ORIGINS=https://recipes.example.com`, then run `docker compose up -d --wait --wait-timeout 600`. Forward the original Host and `X-Forwarded-Proto`. Tandoor trusts the forwarded protocol header, so prevent untrusted direct access to that backend. Keep remote-user authentication disabled unless a trusted authenticating proxy strips all client-supplied identity headers.

<!-- coverage:proxy -->
## Caddy, Nginx and Traefik

`proxy/Caddyfile` obtains HTTPS certificates and routes the domain to loopback. `proxy/nginx.conf` needs your certificate paths; run `nginx -t` before reload. `proxy/traefik.yaml` is dynamic file-provider configuration for an existing Traefik installation with its certificate resolver. The examples assume a proxy on the Docker host. A containerized proxy needs a controlled shared network or reachable host address; its loopback refers to itself. No additional static/media proxy is needed: the official app image includes Nginx.

<!-- coverage:data -->
## Data and every setting

Three project-scoped volumes are created: `database` at `/var/lib/postgresql`, `media` at `/opt/recipes/mediafiles`, and `static` at `/opt/recipes/staticfiles`. PostgreSQL holds recipes, users, spaces, meal plans, shopping lists and integration settings. Images and user uploads live in media. Static assets are generated at each startup and are not user data. The initializer assigns the media/static roots to UID/GID 65534; the application runs without root. Do not change the UID or replace volume ownership blindly.

| Variable | Meaning |
| --- | --- |
| `TANDOOR_VERSION` | Pinned app version, `2.7.2`. |
| `TANDOOR_PORT` | Loopback web port, `8089`. |
| `TANDOOR_SECRET_KEY` | Random Django secret of at least 50 characters; preserve it with backups. |
| `TANDOOR_DB_PASSWORD` | Unique PostgreSQL password set before the first start; changing only `.env` does not alter the existing database role password. |
| `TANDOOR_ALLOWED_HOSTS` | Comma-separated hostnames/IPs without schemes or ports; include loopback for healthchecks. |
| `TANDOOR_CSRF_TRUSTED_ORIGINS` | Comma-separated exact origins including scheme and any nonstandard port; no wildcard. |
| `TZ` | IANA application timezone, `UTC` by default. |

Scripts additionally accept `FOSSARY_ENV_FILE`, `COMPOSE_PROJECT_NAME` and `TANDOOR_BACKUP_DIR`, defaulting to `.env`, project `tandoor` and `backups/`. If you launched with a custom `docker compose -p`, export that same `COMPOSE_PROJECT_NAME` for backup and restore. SMTP, AI, external storage and identity providers remain unconfigured; the recipe does not require their keys.

<!-- coverage:backup -->
## Backup

```bash
bash backup.sh
```

Wait for initialization first. The script stops the application, dumps PostgreSQL and archives the full media volume, `.env` and Compose. It restarts the app only if it was running. Archives use private permissions and unique filenames; encrypt an off-server copy and rehearse recovery. Recipe exports alone do not preserve accounts, meal plans, shopping lists or all settings. Static files are regenerated and excluded from the archive.

<!-- coverage:restore -->
## Restore — replaces current data

Use trusted archives and the matching app/database versions and secrets. On a fresh server, prepare the matching configuration without starting the application:

```bash
docker compose up -d --wait database
docker compose create --no-deps tandoor initialize
bash restore.sh /absolute/path/tandoor-<timestamp>.tar
```

The restore validates archive members, creates a safety backup, stops writers, recreates the application database, replaces media and waits for health. `.env` from the archive is not activated automatically. Verify login, recipe instructions, images, meal plans and shopping lists before reopening access. If restoration fails, keep writers stopped and inspect logs before retrying. A different server also needs corrected host/origin settings.

<!-- coverage:update -->
## Update

Read the [release notes](https://github.com/TandoorRecipes/recipes/releases) and [configuration guide](https://docs.tandoor.dev/system/configuration/). Save the old `.env`, Compose and a verified backup, stop the app, select a reviewed pinned `TANDOOR_VERSION`, then restart:

```bash
bash backup.sh
docker compose stop tandoor
# Edit TANDOOR_VERSION in .env; keep the PostgreSQL major version unchanged.
docker compose pull tandoor
docker compose up -d --wait --wait-timeout 600
docker compose logs --tail=100 tandoor
```

Startup migrates PostgreSQL and rebuilds static assets. Check recipes, media, permissions, meal plans and shopping lists. PostgreSQL major upgrades require a separate export/import plan; never reuse a data directory with a different major image.

<!-- coverage:rollback -->
## Rollback

1. Close external access and stop `tandoor`.
2. Restore the previous `.env` and Compose, preserving the matching secret and the database major version; set the old `TANDOOR_VERSION`.
3. Pull that image, start only the database, and run `docker compose create --no-deps tandoor initialize`. Keep the old app stopped over the newer schema.
4. Run `bash restore.sh /path/to/pre-upgrade.tar`. The safety copy preserves the current state before the old database and media replace it; static assets are regenerated.
5. Verify login, recipes, images, meal plans and shopping lists before reopening the proxy. Changing only the app image does not reverse migrations.

<!-- coverage:removal -->
## Stop or erase

`docker compose down` preserves the volumes. After verifying an external backup, `docker compose down --volumes --remove-orphans` destroys the database, all uploads and static assets. Remove `.env` and local backups separately when they are no longer needed.
