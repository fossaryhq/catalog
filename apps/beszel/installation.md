<!-- coverage:os -->
## Installation
Use Ubuntu 24.04 LTS or Debian 12/13, Docker Engine and Compose >=2.24.0 from the [official repository](https://docs.docker.com/engine/install/). Download the complete recipe.

```bash
cp .env.example .env
chmod 600 .env
openssl rand -hex 24
```
Replace CHANGE_ME in `BESZEL_ADMIN_PASSWORD` with the random value and set your `BESZEL_ADMIN_EMAIL` and actual `BESZEL_URL`.

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait
docker compose ps
```
Open `http://localhost:8090` and sign in with the supplied email/password. On a new database they create the Beszel administrator and PocketBase superuser; environment changes do not rotate existing credentials. Set private credentials before exposing the hub.

<!-- coverage:deployment-vps -->
## VPS
Use a domain, HTTPS, firewall and encrypted off-server backups. Keep 8090 on loopback; expose only the reverse proxy. Restrict /_/ administration to trusted operators.

<!-- coverage:deployment-lan -->
## LAN / VPN
Prefer an SSH tunnel (`ssh -L 8090:127.0.0.1:8090 user@server`) or VPN/proxy. For direct trusted-LAN access, explicitly change the bind address in Compose and restrict it with the firewall. Set BESZEL_URL to the actual browser origin.

<!-- coverage:deployment-domain-https -->
## HTTPS
Point DNS at the proxy and set BESZEL_URL=https://metrics.example.com, then recreate the service. Forward WebSocket upgrades and allow long-lived connections; agents using WebSocket and the live interface need them.

<!-- coverage:proxy-caddy -->
## Caddy
Use proxy/Caddyfile on the host; Caddy handles TLS and WebSocket upgrades.

<!-- coverage:proxy-nginx -->
## Nginx
Obtain the referenced certificate, install proxy/nginx.conf in the http context, run nginx -t and reload. The map selects the appropriate Connection header.

<!-- coverage:proxy-traefik -->
## Traefik
Load proxy/traefik.yaml through the file provider with websecure and the letsencrypt resolver. The sample assumes host Traefik; a container needs a route to the hub instead of host loopback.

<!-- coverage:data -->
## Data / Данные
The named BESZEL_DATA_VOLUME is mounted at /beszel_data: data.db, auxiliary.db, SSH private key id_ed25519, notification state and any native backups. Preserve the whole directory, including WAL files while running. No agent state is mounted here. Changing the volume name selects another installation.

<!-- coverage:backup -->
## Backup
Run bash backup.sh. It stops the hub, archives the entire data volume plus .env and Compose, then restores its prior running/stopped state. Archives have mode 600. Encrypt and copy them off-server; keep each monitored agent's own configuration, token and data separately.

<!-- coverage:restore -->
## Restore / Восстановление
Restore replaces current monitoring data. Use only a trusted archive. Start the recipe once on a new machine, compare archived configuration.env manually (it is not activated), and run bash restore.sh /safe/path/beszel-backup.tar. The script validates required files, takes a safety backup, replaces data and waits for health. Failed extraction leaves the hub stopped. Restored account passwords and SSH key are authoritative; verify old history and that agents reconnect.

<!-- coverage:update -->
## Update / Обновление
Read release notes, back up, set a new explicit BESZEL_VERSION and run docker compose pull && docker compose up -d --wait. Never use latest. Upgrade separately deployed agents to a compatible pinned version and verify metrics. The hub update is an in-place replacement; review future major migration instructions before adopting them.

<!-- coverage:rollback -->
## Rollback / Откат
Stop beszel, restore the previous BESZEL_VERSION in .env, pull and start it once, then restore the matching pre-update archive. A database migrated by a new PocketBase/Beszel version may not work with an older binary; restore the old snapshot rather than reusing migrated files. Verify login, assigned systems and agent connectivity.

<!-- coverage:removal -->
## Removal / Удаление
docker compose down keeps the named volume. For permanent deletion, export a backup first, verify the project and BESZEL_DATA_VOLUME, then run docker compose down --volumes. This destroys accounts, SSH identity and history. Remove .env, proxy/DNS rules and separately deployed agents only when no longer needed.

## Every .env.example parameter

| Variable | Meaning |
| --- | --- |
| `BESZEL_VERSION` | Pinned hub image tag 0.21.1 |
| `BESZEL_PORT` | Loopback host HTTP port, default8090 |
| `BESZEL_URL` | Actual external URL for UI and links |
| `BESZEL_ADMIN_EMAIL` | Email for first administrator and superuser, new DB only |
| `BESZEL_ADMIN_PASSWORD` | Unique random bootstrap password; replace CHANGE_ME |
| `BESZEL_DATA_VOLUME` | Unique persistent volume name |
| `TZ` | IANA timezone, default Etc/UTC |
| `BESZEL_BACKUP_DIR` | Optional private archive destination |

## Connect real systems
Use Add System and the [agent guide](https://beszel.dev/guide/agent-installation) on the machine you intend to monitor. Replace any floating image in the UI-generated command with `henrygd/beszel-agent:0.21.1`. For SSH allow the agent port only from the hub; for WebSocket use TLS. Add Docker socket, host networking or devices only when those integrations are needed. The hub public key is not its private key. SMTP, OIDC, MFA and notification delivery are not configured by this recipe.
