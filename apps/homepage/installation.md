<!-- coverage:os -->
## Ubuntu and Debian
Use Ubuntu 24.04 LTS or Debian 12/13, Docker Engine and Docker Compose >=2.24.0. Install Docker from its [official repository](https://docs.docker.com/engine/install/), including the Compose plugin. Download the complete recipe, including `config/`.

```bash
cp .env.example .env
chmod 600 .env
openssl rand -hex 24
openssl rand -hex 32
```

Put the first random value in `HOMEPAGE_AUTH_PASSWORD`, the second in `HOMEPAGE_AUTH_SECRET`; replace the CHANGE_ME placeholders; do not leave either empty. Configure the URL and host list, then start:

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait
docker compose ps
```

Visit `http://localhost:3000`, enter the password, then edit YAML files in `config/`. The initializer changes ownership to UID/GID 1000; use sudo to edit if needed. Restart `homepage` after changes. The configuration is shared by every signed-in visitor.

<!-- coverage:deployment-vps -->
## VPS
Use a domain, HTTPS, firewall and encrypted off-server backups. Leave port 3000 on loopback and expose only the reverse proxy. Keep the login behind a VPN/IP allowlist or apply an edge password-attempt limit: Homepage has no native rate limiter. The Nginx example includes such a limit; the Caddy and Traefik examples require that protection separately.

<!-- coverage:deployment-lan -->
## Trusted LAN or VPN
The default bind is loopback. Prefer an SSH tunnel (`ssh -L 3000:127.0.0.1:3000 user@server`) or a VPN/proxy. To bind to a trusted LAN, explicitly change the published address in Compose and restrict it with the firewall. Set the exact browser origin in `HOMEPAGE_EXTERNAL_URL` and its host:port in `HOMEPAGE_ALLOWED_HOSTS`. Never use `*` as the host list.

<!-- coverage:deployment-domain-https -->
## Domain and HTTPS
For `https://home.example.com`, set `HOMEPAGE_EXTERNAL_URL=https://home.example.com` and `HOMEPAGE_ALLOWED_HOSTS=home.example.com`. Restart to apply. The URL determines secure session cookies, so it must match the actual browser address.

<!-- coverage:proxy-caddy -->
### Caddy
Use `proxy/Caddyfile` on the host after configuring DNS. Caddy obtains TLS automatically. Add a VPN/IP restriction or an independently configured login-attempt limit.

<!-- coverage:proxy-nginx -->
### Nginx
Use `proxy/nginx.conf`, obtain its certificates first, and run `sudo nginx -t` before reloading. Its `limit_req_zone` belongs in the `http` context. The credential callback is limited to five requests/minute with a burst of five. Adapt the value to your users and monitoring.

<!-- coverage:proxy-traefik -->
### Traefik
Load `proxy/traefik.yaml` through the file provider with the `websecure` entry point and `letsencrypt` resolver. It assumes Traefik runs on the host; a container cannot use the host's loopback without suitable networking. Add a VPN/IP restriction or edge login protection.

<!-- coverage:data -->
## Data and environment
`HOMEPAGE_CONFIG_DIR` (default `./config`) is mounted at `/app/config`, including settings, service links, bookmarks, widgets, custom files and logs. Use an absolute path when moving the recipe. Do not share it with another app. There is no database. Preserve custom icons placed inside this directory if referenced by your configuration.

Every `.env.example` setting:

| Variable | Meaning |
| --- | --- |
| `HOMEPAGE_VERSION` | Pinned application image tag, initially `v2.7.0` |
| `HOMEPAGE_PORT` | Host loopback HTTP port, initially `3000` |
| `HOMEPAGE_CONFIG_DIR` | Configuration directory; initializer makes it owned by 1000:1000 |
| `HOMEPAGE_ALLOWED_HOSTS` | Comma-separated exact browser hosts, including nondefault ports |
| `HOMEPAGE_EXTERNAL_URL` | Actual browser origin including scheme and optional port |
| `HOMEPAGE_AUTH_PASSWORD` | Strong shared dashboard password; required |
| `HOMEPAGE_AUTH_SECRET` | Random session secret, at least 32 characters; required |
| `TZ` | Container timezone, initially `Etc/UTC` |
| `HOMEPAGE_BACKUP_DIR` | Optional private destination for `backup.sh` |

Rotate the password or secret in `.env` and recreate the service. Keep secrets out of custom CSS/JavaScript and static assets, which remain public. Widget API credentials need least privilege. Docker/Kubernetes discovery and OIDC are not enabled by this recipe.

<!-- coverage:backup -->
## Backup

```bash
bash backup.sh
```

The script stops the writer, archives the complete config directory, `.env` and Compose, then restores its previous running/stopped state. Archives have mode 600. Copy them off-server and encrypt them: widget keys and authentication secrets may be inside. Backups exclude the image's ephemeral cache and browser local storage. Copy separately any custom assets stored outside the config directory.

<!-- coverage:restore -->
## Restore
Restore replaces all current configuration. Use only your own trusted archive. Start the recipe once to create its container/mount, compare the archived `configuration.env` manually with your current `.env`, and keep the application version consistent. The archived environment is not automatically executed or activated.

```bash
bash restore.sh /safe/path/homepage-backup.tar
```

The script checks required configuration files before stopping the service, takes a safety backup, replaces the config directory and waits for health. If extraction fails, it keeps the service stopped. Sign in and verify service links and bookmarks. Restoring the old session secret may reactivate still-valid old cookies; rotate it if needed.

<!-- coverage:update -->
## Update
Read upstream release notes, back up, set the new explicit `HOMEPAGE_VERSION`, then run `docker compose pull && docker compose up -d --wait`. Never use `latest`. Verify login and each integration. The documented recipe update is an in-place image replacement; review future major-release instructions before adopting them.

<!-- coverage:rollback -->
## Rollback
Stop `homepage`, restore the previous pinned tag in `.env`, pull it, start once, then restore its pre-update archive with `restore.sh`. Compare the saved environment and test login/widgets. Homepage has no database migration in this recipe, but newer YAML options may not work with an older version: restore matching configuration rather than keeping newer files.

<!-- coverage:removal -->
## Stop and remove
`docker compose down` removes containers/networks and keeps bind-mounted configuration. For permanent removal, first export a backup, run `docker compose down --volumes`, and explicitly remove only your chosen `HOMEPAGE_CONFIG_DIR` and private `.env` after checking the absolute paths. This destroys configuration and any widget keys inside it. Remove DNS/proxy rules and backups separately when no longer needed.

[Official authentication guidance](https://gethomepage.dev/installation/) explains the password/OIDC gate, public static files, Host guard and absence of native login rate limiting.
