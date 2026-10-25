<!-- coverage:os -->
# Install IT Tools

Requires Docker Engine, Compose >=2.24, 1 CPU, 128 MB RAM (256 MB recommended) and 1 GB disk for the image. Tested on amd64; the image also publishes arm64.

```sh
cp .env.example .env
docker compose up -d --wait
```

Open `http://127.0.0.1:8084`. There is no login. For a remote server use `ssh -L 8084:127.0.0.1:8084 user@server`.

## Environment

- `IT_TOOLS_VERSION`: explicit official tag `2024.10.22-7ca5933`.
- `IT_TOOLS_PORT`: loopback HTTP port, initially `8084`.
- `IT_TOOLS_BACKUP_DIR`: optional backup directory, otherwise `./backups`.

`config/nginx.conf` sets unprivileged container port 8080 and temporary files under `/tmp`. UID 101 reads it without write access. The application is static: runtime VITE variables do not change the build.

<!-- coverage:deployment-vps -->
## VPS

Keep the port firewalled on a VPS. Use an SSH tunnel, VPN or separately protected HTTPS gateway.

<!-- coverage:deployment-lan -->
## LAN / VPN

Use a tunnel or VPN proxy for home access. Publishing the interface grants use to everyone the network permits; there are no accounts.

<!-- coverage:deployment-domain-https -->
## HTTPS

Set DNS and configure one proxy sample below. Keep the recipe on loopback; HTTPS alone does not add login.

<!-- coverage:proxy-caddy -->
## Caddy

Set the domain and port in `proxy/Caddyfile`. The sample assumes host-based Caddy with automatic TLS.

<!-- coverage:proxy-nginx -->
## Nginx

Set the domain, port and TLS certificate paths in `proxy/nginx.conf`. This external proxy is separate from the static server in the container.

<!-- coverage:proxy-traefik -->
## Traefik

Load `proxy/traefik.yaml` through a file provider, with websecure and letsencrypt. A containerized proxy needs separate networking; its loopback does not reach the host.

<!-- coverage:data -->
## Data / Данные

The server holds only env, Compose and config/nginx.conf. Favorites, language, theme and some tool inputs are in browser local storage. Server backup is not browser-data backup.

<!-- coverage:backup -->
## Backup

Run `./backup.sh`. It archives config, env and Compose without stopping the static server. Keep an off-server copy; encrypt it if you added secrets. Retain the browser profile separately.

<!-- coverage:restore -->
## Restore / Восстановление

`./restore.sh backups/it-tools-TIMESTAMP.tar.gz` validates the archive and Nginx syntax before replacement, makes a safety backup and starts the server with restored config. Use trusted archives and the matching version. Env/Compose are not activated automatically: compare them manually. Browser data is not restored.

<!-- coverage:update -->
## Update / Обновление

Review release notes, back up configuration, set an explicit tag and run `docker compose pull && docker compose up -d --wait`. Verify a real browser conversion. The current upstream has no newer stable release since 2024.

<!-- coverage:rollback -->
## Rollback / Откат

Return to the saved tag and tested configuration from backup. There is no server database; a new version may change browser storage independently.

<!-- coverage:removal -->
## Removal / Удаление

`docker compose down` removes the container and retains local config/env and browser data. Delete local files separately after backup; clearing the browser site deletes its preferences.

## Verification

`./smoke-test.sh` uses Docker, Bash, curl, Python 3, Node >=22 and npm. It installs Playwright 1.62.1 and Chromium into a temporary test setup; Chromium system libraries must be available. It mutates only its own temporary recipe copy and removes it.
