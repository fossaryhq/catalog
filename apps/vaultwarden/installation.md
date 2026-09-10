### 1. Check the server

Budget at least 1 CPU, 256 MB of RAM, and 1 GB of local disk; 512 MB of RAM plus
room for attachments and backups is more comfortable. Upstream publishes no
formal minimum, so these are our conservative figures for this recipe. You need
Ubuntu 22.04+ or Debian 12+ with Docker Engine and Docker Compose v2.24+.

```bash
docker --version
docker compose version
```

### 2. Prepare files and variables

Put the recipe files in a dedicated directory and create a private `.env`:

```bash
mkdir -p ~/services/vaultwarden
cd ~/services/vaultwarden
cp .env.example .env
chmod 600 .env
```

Set `VAULTWARDEN_DOMAIN` to the real external URL without a trailing slash.
`VAULTWARDEN_VERSION` pins the image; `VAULTWARDEN_PORT` selects the local port;
`VAULTWARDEN_DATA_VOLUME` names the volume; `VAULTWARDEN_SIGNUPS_ALLOWED` and
`VAULTWARDEN_INVITATIONS_ALLOWED` control user enrollment; `TZ` sets the time
zone. All persistent data lives under `/data` in the volume.

### 3. Create the first account

The web vault will not talk to a server over plain HTTP. In 1.37.2 (web vault
2026.7.0) every address the client calls must start with `https://`, and
`localhost` is not an exception: over an SSH tunnel to `http://localhost:8000`
the page loads and the registration form then fails with "Insecure URL not
allowed. All URLs must use HTTPS." Set up the reverse proxy and its certificate
first — see "Domain and HTTPS" below — and register through the HTTPS address.
`curl --fail http://127.0.0.1:8000/alive` still answers over plain HTTP, so a
tunnel is still how you check that the container is up before a certificate
exists.

Sign-ups are closed by default, so the first account needs a brief exception.
Set `VAULTWARDEN_SIGNUPS_ALLOWED=true` in `.env` and start the container:

```bash
docker compose pull
docker compose up -d
docker compose ps
```

Keep that window short — while registration is open, anyone who reaches the
address can take an account. Restricting the proxy to your own IP address for
those few minutes is the safer version.

Open `https://vault.example.com`, click **Create account**, and enter the email
address and a name. On the next screen set the master password. It is the only
key to the vault and there is no recovery flow: store it in another password
manager or write it down and keep it somewhere safe. Then close registration
again — set `VAULTWARDEN_SIGNUPS_ALLOWED=false` in `.env` and apply it:

```bash
docker compose up -d
```

Sign in and add the first item to confirm the vault works end to end:
**New → Login**, then a name, the username, the password and the site address,
and **Save**. **Tools → Generator** creates a password without leaving the page.
Items are encrypted in the browser, so the server stores neither the master
password nor the contents of the vault.

### VPS deployment

<!-- coverage:deployment-vps -->

Keep the `127.0.0.1` bind on a VPS, block port 8000 externally, and publish the
service only through an HTTPS reverse proxy. Check the built-in healthcheck:

```bash
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:8000/alive
```

### Trusted LAN access

<!-- coverage:deployment-lan -->

A LAN without a public domain still needs HTTPS, because the web vault refuses
a plain-HTTP address from anywhere. Issue a certificate locally — Caddy does it
with `tls internal`, or use `mkcert` — and install that certificate authority on
every device that opens the vault; an SSH tunnel or a VPN alone is not enough.
If the reverse proxy runs on another trusted LAN host, replace `127.0.0.1` in
`compose.yaml` with the server's specific LAN address and restrict the port to
the proxy address at the firewall. Do not expose the backend on `0.0.0.0`
without network restrictions.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Replace `vault.example.com` in `.env` and the chosen `proxy/` file with the same
domain. `proxy/Caddyfile` obtains a certificate automatically;
`proxy/nginx.conf` expects a Certbot certificate; `proxy/traefik.yaml` uses the
`letsencrypt` resolver. All examples proxy WebSockets over the main port and
pass the client address in `X-Real-IP`, which is the header Vaultwarden reads by
default — without it every login attempt looks like it came from the proxy, and
the rate limiter counts them as one client. `/admin` → **Diagnostics** shows
this as **IP header: Match**. If Traefik runs in a container, replace
`127.0.0.1` with a reachable host-gateway address.

Check the public endpoint with `curl --fail https://vault.example.com/alive`.
The web vault and the mobile clients both insist on a complete, valid
certificate chain — a partial chain fails on Android while a browser still
accepts it.

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops Vaultwarden, archives the complete `/data` volume, and starts
the container again. This captures SQLite and its WAL consistently. The archive
contains the database, attachments, Sends, RSA keys, and possible secrets from
`config.json`, so it is written `0600` and owned by root — read it with `sudo`,
encrypt it, and keep at least one copy off-server. Upstream
recommends regular, at least daily backups and periodic restore tests.

### Restore

<!-- coverage:restore -->

Restore completely replaces the volume contents with the selected archive:

```bash
./restore.sh ./backups/vaultwarden-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
curl --fail http://127.0.0.1:8000/alive
```

The script creates a safety backup of current data before replacement. Do not
mix files from different snapshots: `db.sqlite3` and `db.sqlite3-wal`, when
present, must come from the same stopped instance.

### Update

<!-- coverage:update -->

Create a backup, read the release notes, and check client compatibility. Change
only the pinned `VAULTWARDEN_VERSION`, then run:

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 vaultwarden
```

### Rollback

<!-- coverage:rollback -->

Do not run an old image over a database migrated by a newer release. Restore the
previous `VAULTWARDEN_VERSION` in `.env`, stop the service, and restore the
archive created before updating:

```bash
docker compose pull
docker compose stop vaultwarden
./restore.sh ./backups/vaultwarden-before-update.tar.gz
docker compose up -d
```

Review the release notes: some data-format changes can prevent a downgrade
without restoring the complete, consistent `/data` backup.

### Stop and remove

<!-- coverage:removal -->

`docker compose down` removes the container but preserves the volume. To remove
everything irreversibly after checking the backup:

```bash
docker compose down
docker volume rm vaultwarden-data
rm -rf ~/services/vaultwarden
```

Sources: [official installation](https://github.com/dani-garcia/vaultwarden/blob/1.37.2/README.md),
[configuration](https://github.com/dani-garcia/vaultwarden/wiki/Configuration-overview),
[HTTPS](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-HTTPS),
[backup](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault), and
[admin page](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-admin-page).
