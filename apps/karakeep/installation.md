## Prepare the server

Use 64-bit Ubuntu 22.04+ or Debian 12+, Docker Engine, and Compose v2.24+. Allow two cores, 2 GB RAM minimum (4 GB recommended), and 10 GB disk plus saved content. These are planning estimates, not a capacity benchmark.

```bash
mkdir -p ~/services/karakeep
cd ~/services/karakeep
# Copy every recipe file, including proxy/ and the scripts, here.
cp .env.example .env
chmod 600 .env
openssl rand -hex 32
openssl rand -hex 32
```

Put the two different generated values in `KARAKEEP_AUTH_SECRET` and `KARAKEEP_MEILI_KEY`. The scripts source `.env` as trusted shell configuration. Use shell-safe values and protect it from other users.

| Parameter | Meaning |
| --- | --- |
| `KARAKEEP_VERSION` | Exact application tag, initially `0.34.1`, without `v`. |
| `KARAKEEP_PORT` | Loopback host port, default `3000`. |
| `KARAKEEP_URL` | Exact browser origin, initially `http://localhost:3000`; use the public HTTPS origin behind a proxy. Also restricts trusted authentication origins. |
| `KARAKEEP_AUTH_SECRET` | Random session/authentication secret; keep it with the backup. |
| `KARAKEEP_MEILI_KEY` | Independent random key shared by the application and Meilisearch. |
| `KARAKEEP_DISABLE_SIGNUPS` | `true` normally; temporarily set `false` to create the first account through the SSH tunnel. |
| `TZ` | IANA time zone, default `Etc/UTC`. |
| `KARAKEEP_BACKUP_DIR` | Optional absolute backup directory; empty uses `backups/` beside the recipe. |

The `data` named volume holds SQLite, uploaded files, saved pages, and queue state under `/data`. The `search` volume holds the Meilisearch index under `/meili_data`. Chrome state is disposable. Compose scopes both volumes to the project; keep the project name stable. Neither the search API nor Chrome's DevTools port is published.

## Start and create an account

Keep the reverse proxy disabled. Set `KARAKEEP_DISABLE_SIGNUPS=false`, then:

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait --wait-timeout 600
curl --fail http://127.0.0.1:3000/api/health
```

From your computer run `ssh -L 3000:127.0.0.1:3000 user@server`. Open `http://localhost:3000`, sign up with a unique password, and verify login. Set `KARAKEEP_DISABLE_SIGNUPS=true` and recreate the app:

```bash
docker compose up -d --wait --wait-timeout 600 karakeep
```

Only publish the proxy after signup is closed. There are no committed account credentials. Additional accounts require another controlled registration window. AI, SMTP, and OIDC are not configured. Do not add an external AI key unless you accept its privacy and billing terms.

## VPS

<!-- coverage:deployment-vps -->

Complete the account setup through the tunnel first. Set `KARAKEEP_URL=https://keep.example.com`, configure DNS and an HTTPS proxy, and recreate Karakeep. Permit only SSH, HTTP, and HTTPS through the firewall. Keep port 3000 bound to loopback and store encrypted backups off-server.

## Trusted local network

<!-- coverage:deployment-lan -->

Use the SSH tunnel or an HTTPS proxy reachable from your trusted LAN/VPN. Keep the loopback binding when using a host proxy. If you deliberately bind a private interface, restrict it with a firewall and set `KARAKEEP_URL` to the exact origin people open. Do not expose a registration window to untrusted users.

## Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Choose a sample in `proxy/`. Caddy obtains certificates; Nginx needs your certificate paths; Traefik needs the `websecure` entry point and `letsencrypt` resolver. These host-proxy samples forward to `127.0.0.1:3000`. A container proxy must share a network with Karakeep and use `karakeep:3000`; its loopback is not the host loopback.

Replace the example hostname and keep `KARAKEEP_URL` identical to the external origin. Forward `Host` and `X-Forwarded-Proto` correctly; an HTTPS origin uses secure cookies. The Nginx sample permits 50 MB request bodies. Test login and an upload over the final URL. Do not publish ports 7700 or 9222.

## Backup

<!-- coverage:backup -->

```bash
./backup.sh
```

The script stops Karakeep and Meilisearch, archives both complete volumes plus active `.env` and Compose, and restarts only the services that were running. The private archive is `backups/karakeep-<timestamp>.tar`. SQLite and its WAL must be copied together while writers are stopped. Keep the search index with the matching engine version.

Encrypt and copy this archive off-server. It contains accounts, private notes, pages, files, keys, and secrets. A personal export or server-to-server CLI migration does not replace this backup.

## Restore

<!-- coverage:restore -->

**Restore replaces both volumes.** Use a trusted archive and the matching application and Meilisearch versions. On a fresh server, copy the recipe, inspect the archived `compose.yaml` and `configuration.env`, and recreate compatible active configuration first. Archived configuration is not activated automatically.

```bash
docker compose up -d --wait --wait-timeout 600
./restore.sh ./backups/karakeep-TIMESTAMP.tar
curl --fail http://127.0.0.1:3000/api/health
```

The script checks archive members, creates a safety backup, replaces both volumes, and waits for health. If replacement fails, keep the services stopped until you restore a verified archive. Sign in, read a private note, open a saved file, and search for known content. The smoke test verifies an account, private note, and a stored file after removal of both original volumes; it does not prove recovery across versions.

## Update

<!-- coverage:update -->

1. Read the [release notes](https://github.com/karakeep-app/karakeep/releases) and create an off-server backup.
2. Change `KARAKEEP_VERSION` to the reviewed exact version. Change the separately pinned Chrome image only after reviewing its release and compatibility.
3. Run `docker compose pull`, then `docker compose up -d --wait --wait-timeout 600`. Check logs, login, a saved page, and search.
4. Treat a Meilisearch version change as a separate migration. Follow the [official index upgrade guide](https://github.com/karakeep-app/karakeep/blob/v0.34.1/docs/docs/06-administration/10-meilisearch-upgrade.md): take a complete backup, use the migration option documented for that exact engine version, then remove it. Do not start a new engine on old data without a migration or a deliberate index rebuild.

Application migrations run at startup. Never use `latest` or `release` as a deployment tag. A successful healthcheck alone does not prove that search and saved content survived.

## Rollback

<!-- coverage:rollback -->

Do not run an older app on a migrated SQLite database or an older Meilisearch on a newer index.

1. Keep the pre-update archive and the matching recipe/configuration.
2. Stop writers: `docker compose stop karakeep meilisearch`.
3. Restore the old exact application and sidecar versions in active Compose and `.env`; retain matching secrets. Pull those images.
4. Run `docker compose create` without starting them on the new data.
5. Run `./restore.sh ./backups/karakeep-BEFORE-UPDATE.tar`, then verify login, notes, saved files, and search. The safety backup can archive stopped containers without running the old app on new state.

## Stop and remove

<!-- coverage:removal -->

`docker compose down` keeps the volumes. After verifying an encrypted off-server backup, `docker compose down --volumes` permanently removes the library and index. Deleting the recipe directory also deletes local configuration and backups. Do not use global Docker pruning commands.

Sources: [Docker deployment](https://docs.karakeep.app/installation/docker), [configuration](https://docs.karakeep.app/configuration), [security](https://docs.karakeep.app/administration/security-considerations), [server migration limits](https://docs.karakeep.app/administration/server-migration).
