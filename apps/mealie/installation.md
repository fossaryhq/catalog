## Requirements

Use a 64-bit Ubuntu 22.04+ or Debian 12+ server with Docker Engine and Compose v2.24+. The official image supports amd64 and arm64; 32-bit ARM is unsupported. Plan for at least 1 CPU core, 1 GB RAM, and 5 GB free disk for the app and recipe images. More storage is needed as you upload photographs.

## Prepare the recipe

```bash
mkdir -p ~/services/mealie
cd ~/services/mealie
# Copy compose.yaml, .env.example, backup.sh, restore.sh, and proxy/ here.
cp .env.example .env
chmod 600 .env
```

Edit `.env` before the first start:

- `MEALIE_VERSION` is the pinned upstream release; review release notes before changing it.
- `MEALIE_PORT` is the host port, default `9925`. Compose binds it to `127.0.0.1`.
- `MEALIE_BASE_URL` is the address used in links and callbacks. Set the public HTTPS URL when using a domain.
- `PUID` and `PGID` set the ownership IDs used for files in the data volume.
- `TZ` sets the server time zone.
- `MEALIE_DEFAULT_LOCALE` sets the initial interface language to `en` or `ru`.
- `MEALIE_DATA_VOLUME` names the volume containing the SQLite database, recipe images, and other app data.

## Start and sign in

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait --wait-timeout 300
docker compose ps
curl --fail http://127.0.0.1:9925/api/app/about
```

Open `http://127.0.0.1:9925` on the server and sign in with the initial account (`changeme@example.com` / `MyPassword`). Change this published default password immediately in account settings before making the service reachable to anyone else. Signup is disabled in this recipe. Invite household members from Mealie rather than enabling open signup.

## VPS

<!-- coverage:deployment-vps -->

Keep the host port on loopback. Point a domain to the server, configure one of the HTTPS proxy examples below on the host, allow SSH/HTTP/HTTPS through the firewall, and keep port 9925 private. First sign in over loopback and replace the published initial password; only then make the domain reachable. Set `MEALIE_BASE_URL` to the public HTTPS URL before first start so generated links and authentication callbacks use the right address. Recipe imports require outbound internet access.

## Trusted local network

<!-- coverage:deployment-lan -->

For one-off access, use an SSH tunnel:

```bash
ssh -L 9925:127.0.0.1:9925 user@server
```

Then open `http://localhost:9925`. To share it on a LAN, place Mealie behind a trusted HTTPS proxy or change the published bind to one specific private IP and restrict access with a firewall. Do not expose the application directly to the public internet over plain HTTP.

## Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Set `MEALIE_BASE_URL=https://recipes.example.com`, point DNS at the proxy, and use the matching Caddy, Nginx, or Traefik example in `proxy/`. Keep the upstream connection on loopback. For Nginx, the sample permits uploads up to 20 MB; increase that deliberately if you need larger recipe photos.

## Backup

<!-- coverage:backup -->

The persistent volume contains the database and uploaded files. Stop Mealie while archiving it so SQLite and files form a consistent snapshot:

```bash
./backup.sh
```

The archive is written to `backups/` beside the recipe. It may contain private recipes and household information. Protect it like personal data and copy it off the server. Also preserve `.env` separately in a secure location; the initial admin credentials and public URL are needed to operate the restored installation.

## Restore

<!-- coverage:restore -->

Restore replaces the current data volume. The script first makes a safety backup of the current state:

```bash
./restore.sh ./backups/mealie-YYYYMMDDTHHMMSSZ.tar.gz
```

Then check the service and sign in:

```bash
docker compose up -d --wait --wait-timeout 300
curl --fail http://127.0.0.1:9925/api/app/about
docker compose logs --tail=100 mealie
```

The smoke test exercises this backup and restore path on amd64. Keep the image version and `.env` compatible with the archive.

## Update

<!-- coverage:update -->

Read Mealie's release notes and create an off-server backup before an upgrade. Change `MEALIE_VERSION` to the exact reviewed tag in `.env`, then:

```bash
./backup.sh
docker compose pull
docker compose up -d --wait --wait-timeout 300
docker compose logs --tail=100 mealie
```

Do not use `latest`. Database migrations happen on startup; allow the healthcheck to pass before using the app.

## Rollback

<!-- coverage:rollback -->

Do not start an older version against data migrated by a newer release. Set `MEALIE_VERSION` back to the previous tag and restore the archive made before the upgrade:

```bash
docker compose down
./restore.sh ./backups/mealie-BEFORE-UPDATE.tar.gz
docker compose up -d --wait --wait-timeout 300
```

## Stop and remove

<!-- coverage:removal -->

Stop the service while retaining its data:

```bash
docker compose down
```

To remove the app and its data permanently, first verify an off-server backup, then:

```bash
docker compose down --volumes
rm -rf ~/services/mealie
```

This deletes recipes, accounts, meal plans, shopping lists, and uploaded images.

## Security notes

Mealie's URL import feature makes outbound requests from the server. Give access only to trusted users, and keep the app isolated from sensitive internal services where practical. The initial account has a password published in upstream documentation; change it before allowing access beyond loopback. Disabling signup does not make shared accounts safe: invite household members and use unique passwords. The official default `HOST_IP=*` trusts forwarded headers from every connecting source. Restrict it to the proxy address or network when a proxy is used; only that proxy should be able to reach the app.

Sources: [SQLite installation](https://docs.mealie.io/documentation/getting-started/installation/sqlite/), [security considerations](https://docs.mealie.io/documentation/getting-started/installation/security/), [backups and restore](https://docs.mealie.io/documentation/getting-started/usage/backups-and-restoring/), and [release v3.29.0](https://github.com/mealie-recipes/mealie/releases/tag/v3.29.0).
