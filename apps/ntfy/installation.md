## Requirements and credentials

Use Ubuntu 22.04+ or Debian 12+ on amd64/arm64 with Docker Engine and Compose v2.24+. Plan for 1 CPU, 128 MB RAM (256 MB recommended), and 2 GB disk plus growing message/attachment caches and off-server backups. Only amd64 was exercised.

Copy the complete recipe, scripts, and proxy/ directory. Create .env with mode 600, choose a strong unique administrator password, and use the pinned image to hash it:

```bash
cp .env.example .env
chmod 600 .env
docker run --rm -it binwiederhier/ntfy:v2.33.1 user hash
```

Put the printed hash in .env as `NTFY_AUTH_USERS='ntfyadmin:<bcrypt-hash>:admin'`. Single quotes preserve literal `$`; do not double them in .env. Keep the original password in a password manager. Do not paste the hash directly into Compose, where escaping rules differ.

| Parameter | Meaning |
| --- | --- |
| `NTFY_VERSION` | Pinned app tag including v, initially v2.33.1. |
| `NTFY_PORT` | Host loopback port, initially 8083. |
| `NTFY_URL` | Exact browser origin, initially http://localhost:8083; external HTTPS URL behind a proxy. Used for attachment/client URLs. |
| `NTFY_AUTH_USERS` | Single-quoted name:bcrypt:role administrator entry. Authoritative on startup, not a one-time setup password. |
| `NTFY_DATA_VOLUME` | Named volume for cache.db, user.db and attachments/. |
| `TZ` | IANA time zone, default Etc/UTC. |
| `NTFY_BACKUP_DIR` | Optional absolute backup path; defaults to backups/ beside the recipe. |

## Start and verify

The scripts source .env as trusted shell configuration. Do not use a file from an untrusted source. The helper initializes the volume, then ntfy runs as UID/GID 1000 with a read-only root. Start and sign in as ntfyadmin with the password you hashed:

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait --wait-timeout 180
curl --fail http://127.0.0.1:8083/v1/health
```

Open NTFY_URL, sign in, and subscribe to `household`. Send a test notification; curl prompts for the password without putting it in the command:

```bash
curl --fail -u ntfyadmin -d 'Test notification' http://127.0.0.1:8083/household
```

## VPS

<!-- coverage:deployment-vps -->

Set NTFY_URL to the external HTTPS origin and put a host proxy in front of loopback port 8083. Permit SSH/HTTP/HTTPS only, verify login and blocked anonymous topic access, and keep an encrypted backup off the VPS. The browser UI can load before login, but protected topic data cannot be read anonymously.

## Trusted local network

<!-- coverage:deployment-lan -->

Use `ssh -L 8083:127.0.0.1:8083 user@server` with the matching local URL, or publish through an HTTPS LAN/VPN proxy. If you deliberately bind to a private host IP, restrict it with a firewall. Keep authentication on. Attachment URLs remain bearer links even on a private topic.

## Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Set `NTFY_URL=https://notify.example.com` and recreate the service. proxy/ includes host-side Caddy, Nginx and Traefik examples for 127.0.0.1:8083. Caddy manages certificates; Nginx needs certificate paths; Traefik needs websecure and a letsencrypt resolver. A containerized proxy needs a shared network and internal port 8080 instead of its own loopback. Keep websocket upgrades and streaming responses enabled; Nginx buffering is disabled and the request cap is 15 MB. Forwarded client-IP trust remains disabled, so visitors share the proxy IP's rate limit; do not enable header trust until only the actual proxy can reach the service and client-supplied headers are sanitized.

## Accounts and retention

The declarative administrator entry is reapplied on every startup. To rotate it, generate a new hash, update the single-quoted NTFY_AUTH_USERS entry, and recreate ntfy. For automation create a regular account and explicit topic permissions; run these interactive commands and create a token in that account's UI:

```bash
docker compose exec ntfy ntfy user add backupjob
docker compose exec ntfy ntfy access backupjob backups rw
```

Messages and attachments are cached for seven days; attachment storage is capped at 1 GB and individual files at 15 MB. Clearing browser history does not erase the server cache. Attachment URLs can be shared, so treat them as secrets and encrypt sensitive files before upload. Web Push, iOS upstream polling, Firebase, SMTP and calls are not enabled; configure and test background delivery separately using the official documentation.

## Backup

<!-- coverage:backup -->

Run `./backup.sh`. It stops the writer and archives the entire named volume with .env and Compose in one mode-600 backups/ntfy-<timestamp>.tar. The payload contains cache.db, user.db, attachments, account settings, subscriptions, ACLs, tokens, and the administrator hash. It preserves the previous running/stopped state. Encrypt the archive and copy it off-server; a live SQLite file or a browser export alone is not a complete backup.

## Restore

<!-- coverage:restore -->

**Restore replaces the current volume.** Use a trusted backup, the matching pinned app version and NTFY_AUTH_USERS from archived configuration.env. Compare the saved environment manually before restore; it is not activated. On a new host initialize the matching recipe first. The script validates the payload and both database names, creates a safety backup, stops the writer and replaces data. A replacement failure leaves ntfy stopped.

```bash
docker compose up -d --wait --wait-timeout 180
./restore.sh ./backups/ntfy-TIMESTAMP.tar
curl --fail http://127.0.0.1:8083/v1/health
```

Sign in, read a saved message, download a sample attachment and publish a new message with a regular account/token. Confirm another topic and anonymous reads remain denied. Original retention timestamps still apply: recovery does not extend an old attachment's lifetime.

## Update

<!-- coverage:update -->

Read upstream release notes, make and export a backup, and change NTFY_VERSION to a reviewed fixed tag. Run `docker compose pull` and `docker compose up -d --wait --wait-timeout 180`, then inspect logs, log in, and test publishing/subscribing with a non-admin account. SQLite migrations run at startup. Preserve credentials and review client/server compatibility; do not use latest.

## Rollback

<!-- coverage:rollback -->

Do not run an older server on a database migrated by a newer version. Stop ntfy, set the old fixed version and matching NTFY_AUTH_USERS in .env, pull and recreate without starting, then restore the complete pre-update backup. The safety backup reads the stopped volume before replacement. Keep the failed installation's archive until recovery is confirmed.

```bash
docker compose stop ntfy
# Set the old pinned version and matching NTFY_AUTH_USERS in .env.
docker compose pull ntfy
docker compose create ntfy
./restore.sh ./backups/ntfy-BEFORE-UPDATE.tar
```

## Stop and remove

<!-- coverage:removal -->

`docker compose down` keeps the named data volume. After checking an encrypted off-server backup, `docker compose down --volumes` permanently removes messages, attachments, accounts, tokens, ACLs and settings. Removing the recipe directory also removes .env and any local backups.

Sources: [configuration](https://docs.ntfy.sh/config/), [Docker installation](https://docs.ntfy.sh/install/#docker), [publishing](https://docs.ntfy.sh/publish/), [subscription clients](https://docs.ntfy.sh/subscribe/), [v2.33.1](https://github.com/binwiederhier/ntfy/releases/tag/v2.33.1).
