### 1. Check the Ubuntu or Debian server

Use Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. One CPU
core, 512 MB RAM, and 2 GB disk are enough: the budget is a few megabytes and the
heavy work happens in the client. The official image declares amd64 and arm64.

```bash
docker --version
docker compose version
```

### 2. Prepare the recipe

```bash
mkdir -p ~/services/actual-budget
cd ~/services/actual-budget
cp .env.example .env
chmod 600 .env
```

There is no secret to generate here: Actual asks for the server password in the
browser during the first visit and stores its hash in `server-files`. Keep the
password in a password manager — it is the only thing standing between the
internet and the budget.

Every `.env` variable:

- `ACTUAL_PORT` is the local web port, default `5006`;
- `ACTUAL_LOGIN_METHOD` selects `password`, `openid`, or `header`;
- `ACTUAL_ALLOWED_LOGIN_METHODS` lists the methods the server accepts at all, `password` only in this recipe;
- `ACTUAL_UPLOAD_FILE_SYNC_SIZE_LIMIT_MB`, `ACTUAL_UPLOAD_SYNC_ENCRYPTED_FILE_SYNC_SIZE_LIMIT_MB`, and `ACTUAL_UPLOAD_FILE_SIZE_LIMIT_MB` cap sync and upload sizes;
- `ACTUAL_TIME_ZONE` is an IANA time zone;
- `ACTUAL_DATA_VOLUME` names the volume holding `server-files` and `user-files`;
- `ACTUAL_BACKUP_DIR` selects the host backup directory.

### 3. Start and set the server password

```bash
docker compose config
docker compose pull
docker compose up -d --wait --wait-timeout 600
docker compose ps
curl --fail http://127.0.0.1:5006/health
```

`/health` answers `{"status":"UP"}` once the API and its SQLite store are ready.
Open the public address and set the server password on the bootstrap screen
before anyone else does, then create or import a budget file. A browser that has
opened the budget keeps a full local copy, so the first sync uploads the whole
file.

### VPS deployment

<!-- coverage:deployment-vps -->

Keep `127.0.0.1:${ACTUAL_PORT}:5006`; only an HTTPS proxy on the host can reach
the server. Allow SSH, HTTP, and HTTPS through the firewall and nothing else.
Set the server password immediately after the first start: an instance that is
reachable and not yet bootstrapped hands the budget to whoever finds it. Bank
synchronisation through GoCardless or SimpleFIN is configured inside the
application and requires outbound HTTPS.

### Trusted LAN access

<!-- coverage:deployment-lan -->

Prefer `ssh -L 5006:127.0.0.1:5006 user@server` and open `http://localhost:5006`.
For permanent LAN access, replace the localhost bind with one specific private
IP and restrict the port with a firewall. Note that a browser needs a secure
context for the installable PWA and for the Web Crypto used by end-to-end
encryption, so plain HTTP over the LAN limits both; treat it as a temporary
route rather than the normal one.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Point `budget.example.com` at the server, replace the host in the Caddy, Nginx,
or Traefik example, and open the address once to set the password. The proxy
must allow uploads as large as the budget file — the Nginx sample raises
`client_max_body_size` to 100 MB — and must pass WebSocket upgrades for the sync
connection. Actual builds no absolute URLs of its own, so no base-URL variable
has to match the domain.

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops the server, archives the whole `/data` volume, and stores `.env`
and `compose.yaml` next to it. Stopping matters: a live SQLite file can be
captured mid-write. The archive holds every budget file, the server password
hash, and `.env` itself, so the script writes it `0600` inside a `0700`
directory; keep those permissions when you copy it, encrypt it, and keep the
copy off the server. Actual also writes its own
periodic copies inside the volume and the desktop client keeps local backups;
neither is a substitute for an off-server archive.

### Restore

<!-- coverage:restore -->

Restore irreversibly replaces the data volume. Use the same Actual version with
the active `.env`:

```bash
./restore.sh ./backups/actual-budget-YYYYMMDDTHHMMSSZ.tar
curl --fail http://127.0.0.1:5006/health
```

The script first backs up the state being replaced, recreates the volume,
unpacks the archive, and starts the server.

The round trip is part of `smoke-test.sh`, so every scheduled run of this recipe
sets a server password, backs up, removes the data volume outright, and checks
after the restore that the server is bootstrapped again and that the same
password still logs in. What it does not cover is the size of your own budget
files or the clients: after a restore every browser and desktop app is ahead of
the server, so open each one, and if a client refuses to sync, remove its local
file and download the budget from the server again. Rehearse that part on a
separate machine before you need it.

### Update Actual

<!-- coverage:update -->

Create a backup and read the release notes — Actual ships a release most months
and occasionally migrates the budget format:

```bash
./backup.sh
docker compose pull
docker compose up -d --wait --wait-timeout 600
curl --fail http://127.0.0.1:5006/health
docker compose logs --tail=200 actual
```

Replace the exact `actualbudget/actual-server:26.9.0` tag with a reviewed
version; never use `latest`, `edge`, or `nightly`. After a format migration the
clients update their local copies on the next sync, so update the desktop apps
in the same maintenance window.

### Rollback

<!-- coverage:rollback -->

Never start an older server over budget files a newer version has migrated.
Restore the previous exact tag together with the pre-update archive:

```bash
docker compose down --timeout 60
./restore.sh ./backups/actual-budget-BEFORE-UPDATE.tar
```

Clients that already migrated their local copy must re-download the budget from
the restored server.

### Stop and remove

<!-- coverage:removal -->

`docker compose down` preserves the data volume. After verifying an off-server
backup, remove everything irreversibly:

```bash
docker compose down
docker volume rm actual-data
rm -rf ~/services/actual-budget
```

Substitute the actual name when `ACTUAL_DATA_VOLUME` differs. Budget copies also
live in each browser and desktop client; clear them separately if the data must
be gone everywhere.

Sources: [Docker installation](https://actualbudget.org/docs/install/docker),
[server configuration](https://actualbudget.org/docs/config/),
[backup and restore](https://actualbudget.org/docs/backup-restore/backup), and
[release v26.9.0](https://github.com/actualbudget/actual/releases/tag/v26.9.0).
