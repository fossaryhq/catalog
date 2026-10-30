# Install Netdata

<!-- coverage:installation -->
## Prepare the Linux server

Use Docker Engine and Docker Compose 2.24 or newer on a supported Ubuntu or Debian release. The commands below target Ubuntu 22.04/24.04/26.04 and Debian 12/13; the runtime proof covers one amd64 Linux Docker host, not every distribution. Install Docker from its [Ubuntu](https://docs.docker.com/engine/install/ubuntu/) or [Debian](https://docs.docker.com/engine/install/debian/) instructions. Check:

```bash
docker version
docker compose version
```

Docker administrators can control the host. This recipe reads host metrics and shares its PID namespace. Run it on a host you are authorized to monitor. Rootless Docker and restrictive host policies may limit collection and were not tested.

Put all recipe files in `/srv/netdata`, including `config/`, `proxy/` and both recovery scripts. Before startup:

```bash
cd /srv/netdata
umask 077
cp .env.example .env
chmod 600 .env
chmod 644 config/Caddyfile config/netdata.conf
docker run --rm -it caddy:2.11.7-alpine caddy hash-password
```

Enter a unique password interactively. Save it in a password manager and put the resulting bcrypt hash in the single-quoted `NETDATA_AUTH_HASH` value in `.env`. Set your own username and hostname. The template hash is rejected before the gateway opens HTTP. The public configuration files contain no password and must be readable by the unprivileged gateway.

```bash
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --wait --wait-timeout 300
docker compose ps
```

<!-- coverage:deployment-lan -->
## First access and the local network

Open `http://127.0.0.1:19999/v3/`, enter the gateway username and the original password, then use the local dashboard without signing in to Netdata Cloud. Wait for native measurements to accumulate. The Agent is not claimed by this recipe. `/healthz` is public but contains no metrics; `/api/v1/info` and the dashboard require the password.

For another machine, prefer an SSH tunnel or an encrypted VPN. Do not expose Basic authentication over unencrypted public HTTP. Under Docker Desktop, measurements describe its Linux VM.

<!-- coverage:deployment-vps -->
## VPS

Keep the published port on loopback and connect through SSH before configuring HTTPS:

```bash
ssh -L 19999:127.0.0.1:19999 user@server
```

Allow only SSH and your intended HTTPS ports through the firewall. Do not publish the Agent's internal port or grant Docker socket access. Protect and encrypt off-server backups.

<!-- coverage:deployment-domain-https -->
## Domain and HTTPS

Point your DNS name to the server. The supplied examples use `metrics.example.com`; replace it and retain the gateway's authentication. The outer proxy must forward the client's Authorization header. Verify an anonymous request to `/api/v1/info` still returns 401 and a password-authenticated request succeeds.

<!-- coverage:caddy -->
### Caddy

Use `proxy/Caddyfile` with a host Caddy installation. It terminates HTTPS and forwards to `127.0.0.1:19999`; the inner gateway continues to enforce the password.

<!-- coverage:nginx -->
### Nginx

Use `proxy/nginx.conf` in your existing TLS-enabled server. Obtain a certificate first, replace the example certificate paths and domain, check `nginx -t`, then reload. The sample does not obtain certificates for you.

<!-- coverage:traefik -->
### Traefik

Use `proxy/traefik.yaml` through Traefik's file provider, with your existing `websecure` entrypoint and `letsencrypt` resolver. Join the Traefik container to this Compose project's frontend network (normally `netdata_frontend`). The backend name `gateway` must resolve there. The internal Agent network stays separate.

<!-- coverage:configuration -->
## Configuration and persistent data

| Setting | Meaning |
| --- | --- |
| `NETDATA_VERSION` | Numeric Agent version; Compose adds the official `v` tag prefix. |
| `NETDATA_PORT` | Loopback HTTP port of the authentication gateway, default 19999. |
| `NETDATA_HOSTNAME` | Host label shown by this Agent; choose a useful unique name. |
| `NETDATA_AUTH_USER` | Gateway username. |
| `NETDATA_AUTH_HASH` | Single-quoted bcrypt hash of your gateway password. Changing it rotates access without modifying Agent identity. |
| `TZ` | Container timezone, default `Etc/UTC`. |

`config/netdata.conf` configures the Agent and `config/Caddyfile` configures the password gateway. Both are mounted read-only inside their containers. Edit them on the host and recreate the affected service. The original image supplies its remaining default configuration; additional collector/alert files need explicit mounts and review.

The project-scoped `netdata-lib` volume stores `/var/lib/netdata`, including identity and API keys. `netdata-cache` stores `/var/cache/netdata`, including dbengine history and SQLite metadata. Both are required for a complete recovery. The host filesystem mounts are measurement inputs and are never included in these backup scripts.

<!-- coverage:backup -->
## Backup

```bash
bash backup.sh
```

The script briefly stops the gateway and Agent, archives both volumes and copies configuration, `.env` and Compose into one private archive under `backups/`. It restarts only services that were running. A stopped installation stays stopped. Archives have mode 600 and the backup directory mode 700. Encrypt a copy on a different server; an archive on this host does not protect against host loss.

<!-- coverage:restore -->
## Restore — replaces identity and history

Use a trusted archive and matching Agent version. Preserve the current installation before proceeding:

```bash
bash restore.sh -y backups/netdata-YYYYMMDDTHHMMSS-PID.tar.gz
docker compose ps
```

The script validates the archive before changing data, creates a safety backup, replaces both volumes and waits for health. Current configuration, password hash and image versions stay active. If the installation files were also lost, first extract and review `configuration.env`, `compose.yaml` and `config/` from your own archive, restore `.env` with mode 600, and make the two public config files mode 644. Never source an untrusted archived environment file. Then run the data restore.

<!-- coverage:update -->
## Update

Read the [release notes](https://github.com/netdata/netdata/releases) and make an off-server backup. Change `NETDATA_VERSION` to the reviewed numeric version, then:

```bash
docker compose pull
docker compose up -d --wait --wait-timeout 300
docker compose logs --tail 100 netdata gateway
```

Review a Caddy version change separately in Compose. Recheck authenticated charts and anonymous denial after either image changes. A successful healthcheck alone does not establish that historical data survived.

<!-- coverage:rollback -->
## Rollback

Keep the pre-update archive and recipe files. Stop the updated services, restore the reviewed old Compose/configuration and numeric Agent version, pull those pinned images, then run `restore.sh -y` with the pre-update archive. Do not point an older Agent at a possibly migrated newer database. Verify the original Agent identity and a historical interval after rollback.

<!-- coverage:removal -->
## Stop or remove

`docker compose down` stops the installation and keeps both data volumes. `docker compose down --volumes` permanently removes local identity and history. Keep and verify an off-server backup first. Remove `.env`, configuration and archives separately only when you intend to erase them. Never remove the host directories that the recipe reads for monitoring.

## Official sources

[Container deployment and collector privileges](https://github.com/netdata/netdata/blob/v2.12.2/packaging/docker/README.md), [dashboard access and Cloud-only features](https://github.com/netdata/netdata/blob/v2.12.2/docs/dashboards-and-charts/README.md), [Agent configuration](https://github.com/netdata/netdata/tree/v2.12.2/docs/netdata-agent/configuration).
