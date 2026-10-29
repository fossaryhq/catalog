## Prepare the server

Use Ubuntu 22.04+ or Debian 12+, Docker Engine, and Compose v2.24+. Plan for one CPU core, at least 512 MB RAM (1 GB recommended), and 2 GB disk plus articles and images. ARM64 and ARMv7 images exist but were not tested in this check.

```bash
mkdir -p ~/services/wallabag
cd ~/services/wallabag
# Copy all recipe files, including proxy/ and the scripts, here.
cp .env.example .env
chmod 600 .env
openssl rand -hex 32
openssl rand -hex 24
```

Put the first generated value in `WALLABAG_SECRET` and the second in `WALLABAG_ADMIN_PASSWORD`. Use different values. The initializer refuses the example password, the upstream default password, and passwords shorter than 16 characters. It also refuses the example application secret. The scripts source `.env` as trusted shell configuration; the recommended hexadecimal values need no escaping.

| Parameter | Meaning |
| --- | --- |
| `WALLABAG_VERSION` | Exact image tag, initially `2.6.15`. |
| `WALLABAG_PORT` | Loopback host port, default `8087`. |
| `WALLABAG_URL` | Canonical browser origin, initially `http://localhost:8087`; set the external HTTPS origin behind a proxy. |
| `WALLABAG_SECRET` | Random application/session secret; retain it with the backup. |
| `WALLABAG_ADMIN_PASSWORD` | Administrator password enforced by initialization. Keep the account named `wallabag`; rotate the password here and recreate the stack. |
| `WALLABAG_LOCALE` | Default interface locale, `en` or `ru` for these guides. Account preferences can override it. |
| `TZ` | Container operating-system time zone, default `Etc/UTC`; PHP uses UTC for stored dates. |
| `WALLABAG_BACKUP_DIR` | Optional absolute backup directory; empty uses `backups/` beside the recipe. |

The `data` named volume holds SQLite under `/var/www/wallabag/data/db`, plus other application data. `images` holds cached images under `/var/www/wallabag/web/assets/images`. Both are scoped to the Compose project; keep the project name stable. Container configuration and cache are regenerated from the pinned image and `.env`.

## Start and sign in

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait --wait-timeout 600
curl --fail http://127.0.0.1:8087/api/info
```

The `initialize` service must finish successfully before `wallabag` can start. It uses the official migration command, then replaces the default administrator password. There is no interval in which the published web service accepts the upstream default credentials. Registration stays disabled.

From another computer run `ssh -L 8087:127.0.0.1:8087 user@server`, open `http://localhost:8087`, and sign in as `wallabag` with the password from `.env`. Update the administrator email in account settings. Do not delete or rename this deployment-owned account. An interface password change is replaced on the next initialization; rotate it in `.env` instead. Additional users can be created with the official administrator/console tools.

No SMTP, Redis, RabbitMQ, SSO provider, or mobile client is configured. Native TOTP/email two-factor authentication needs its own setup; verify recovery access before enabling it. Email delivery is unavailable until SMTP is configured.

## VPS

<!-- coverage:deployment-vps -->

Set `WALLABAG_URL=https://read.example.com`, configure DNS and an HTTPS proxy, then recreate the stack. Permit only SSH, HTTP, and HTTPS through the firewall. Leave port 8087 on loopback. Encrypt backups and keep a copy off-server.

## Trusted local network

<!-- coverage:deployment-lan -->

Use the SSH tunnel or an HTTPS proxy available to your trusted LAN/VPN. If you deliberately bind a private interface, restrict it with a firewall and set `WALLABAG_URL` to the exact address people open. Do not expose an HTTP password login to an untrusted network.

## Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Choose a host-proxy example from `proxy/`. Caddy obtains certificates; Nginx needs your certificate paths; Traefik needs the `websecure` entry point and `letsencrypt` resolver. All examples forward to `127.0.0.1:8087`. A containerized proxy needs a shared network and `wallabag:80`, not its own loopback.

Replace the sample hostname, set the matching HTTPS `WALLABAG_URL`, and run `docker compose up -d --wait --wait-timeout 600`. Forward `Host` and `X-Forwarded-Proto` correctly. The Nginx example permits 50 MB requests. Verify login and article capture through the final origin; external proxy and certificate issuance were not exercised in the native smoke.

## Backup

<!-- coverage:backup -->

```bash
./backup.sh
```

Wait for initialization to finish first. The script stops the web application, archives both complete volumes with active `.env` and Compose, and restarts it only if it was running. The private archive is `backups/wallabag-<timestamp>.tar`. Copy SQLite and its WAL together while writers are stopped; a personal article export does not contain every account, OAuth client, and setting.

Encrypt the archive and copy it off-server. It contains private articles, cached images, accounts, tokens, and the deployment-owned administrator password.

## Restore

<!-- coverage:restore -->

**Restore replaces both volumes.** Use a trusted archive and the matching application version. On a new host, copy the recipe and compare archived `configuration.env` and `compose.yaml` with your active configuration first. Archived configuration is not activated automatically; the active `.env` administrator password is enforced during initialization.

```bash
docker compose up -d --wait --wait-timeout 600
./restore.sh ./backups/wallabag-TIMESTAMP.tar
curl --fail http://127.0.0.1:8087/api/info
```

The script validates the payload, creates a safety backup, replaces the complete data/image volumes, and waits for health. A replacement failure leaves the app stopped. Sign in, open a private article, check its tags, and verify cached images or a mobile client's API access. The amd64 smoke removes both original volumes before restoration and verifies an OAuth client, article, tags, anonymous access rejection, and a marker in the image volume.

## Update

<!-- coverage:update -->

Read the [release notes](https://github.com/wallabag/wallabag/releases), create an off-server backup, and change `WALLABAG_VERSION` to the reviewed exact tag. Then:

```bash
docker compose pull
docker compose up -d --wait --wait-timeout 600
docker compose logs --tail=100 initialize wallabag
```

Initialization applies migrations before the web app starts and re-enforces the active administrator password. Verify login, a saved article, tags, and an API client after updating. Keep the pre-update archive. Never use `latest` or assume an older image can read a migrated database.

## Rollback

<!-- coverage:rollback -->

1. Keep the pre-update archive and matching recipe/configuration.
2. Stop writers: `docker compose stop wallabag`.
3. Set the old exact image version in `.env` and restore any matching Compose changes. Pull the old image.
4. Run `docker compose create` without starting the old initializer or app on the migrated database.
5. Run `./restore.sh ./backups/wallabag-BEFORE-UPDATE.tar`. Only after replacement will initialization and the app start. Check login, private articles, tags, images, and API access.

The safety backup reads the stopped volumes without starting an older app on new data. Restoring data does not automatically restore the archived administrator password: compare active `.env` explicitly.

## Stop and remove

<!-- coverage:removal -->

`docker compose down` removes containers and keeps the volumes. After verifying an encrypted off-server backup, `docker compose down --volumes` permanently removes accounts, articles, settings, OAuth clients, and cached images. Deleting the recipe directory also removes local backups and configuration. Avoid global Docker pruning.

Sources: [official Docker image](https://github.com/wallabag/docker), [documentation](https://doc.wallabag.org/), [console commands](https://github.com/wallabag/wallabag/blob/2.6.15/doc/content/admin/console_commands.md), [OAuth API](https://github.com/wallabag/wallabag/blob/2.6.15/doc/content/developer/api/oauth.md).
