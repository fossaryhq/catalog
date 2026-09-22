### 1. Check the server

You need Ubuntu 22.04+ or Debian 12+ with Docker Engine and Docker Compose
v2.24+. Budget 1 CPU, 128 MB of RAM, and 1 GB of local disk; 256 MB of RAM leaves
room for more checks and history. This recipe uses SQLite and needs no separate
database.

```bash
docker --version
docker compose version
```

### 2. Prepare the files and variables

Put `compose.yaml`, `.env.example`, `config/`, `backup.sh`, `restore.sh`, and
`proxy/` in a directory of their own:

```bash
mkdir -p ~/services/gatus
cd ~/services/gatus
cp .env.example .env
chmod 600 .env
```

`.env` holds the pinned `GATUS_VERSION`, local `GATUS_PORT`, Docker volume name,
`GATUS_CONFIG_DIR`, and the dashboard credentials. Keep the configuration
directory at `./config` unless you also want backups to read it elsewhere.
Replace `change-me`. Gatus stores a bcrypt hash, not a plain password; these
commands create a password and the Base64-encoded hash to put in
`GATUS_PASSWORD_BCRYPT_BASE64`:

```bash
password="$(openssl rand -base64 32)"
printf 'Password: %s\n' "$password"
htpasswd -bnBC 9 "" "$password" | tr -d ':\n' | base64 -w0
printf '\n'
```

`htpasswd` comes from `apache2-utils` on Ubuntu and Debian. Save the printed
password in a password manager; the hash in `.env` cannot be turned back into it.

The monitored targets live in `config/config.yaml`. The included self-check
proves that scheduling, condition evaluation, SQLite storage, and the dashboard
work before you add your own services. Keep secrets for alert providers in
`.env`, pass them through `compose.yaml`, and reference their environment names
from the configuration instead of writing tokens into YAML.

### 3. Start the container on a VPS

<!-- coverage:deployment-vps -->

```bash
docker compose pull
docker compose up -d
docker compose ps
curl http://127.0.0.1:8080/health
```

The last command should print `{"status":"UP"}`. Gatus has no image-level
Docker healthcheck, so verify both `/health` and a completed endpoint result in
the dashboard after startup.

### 4. Open the dashboard and add checks

Use an SSH tunnel before the reverse proxy exists:

```bash
ssh -L 8080:127.0.0.1:8080 user@server.example
```

Open `http://localhost:8080` and sign in with the credentials from `.env`. Wait
for **Gatus health** to turn green and open it to see the successful conditions.

Add an endpoint to `config/config.yaml`, for example:

```yaml
  - name: Public website
    group: Production
    url: https://www.example.com/
    interval: 1m
    conditions:
      - "[STATUS] == 200"
      - "[CERTIFICATE_EXPIRATION] > 48h"
      - "[RESPONSE_TIME] < 1000"
```

Run `docker compose restart gatus` and inspect the logs. Start with a status,
certificate, and generous response-time condition; tighten the threshold only
after observing normal traffic. A green HTTP check proves that this request
worked, not that every feature of the target application works.

### Local network

<!-- coverage:deployment-lan -->

Keep the localhost bind and use an SSH tunnel. If the dashboard must be visible
on a trusted LAN, replace `127.0.0.1` in `compose.yaml` with the server's LAN
address, such as `192.168.1.10`, and block port 8080 on the external interface.
Do not bind it to every interface merely for convenience.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

The examples in `proxy/` forward `status.example.com` to the local port. Replace
that name with your domain. Caddy obtains a certificate automatically; the Nginx
example expects Certbot files; the Traefik example uses a resolver named
`letsencrypt`. For Traefik running in a container, replace `127.0.0.1` with a
host gateway address that its container can reach.

Basic Auth remains enabled behind the proxy. Gatus also supports OIDC, but moving
authentication to an identity provider requires an OIDC client secret and a
deliberate edit of the `security` block; do not enable both modes by accident.

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops Gatus so SQLite's database, WAL, and shared-memory files form a
consistent set, then archives the data volume together with `config/`. It starts
the container again before returning. Keep an encrypted copy off the server;
the archive contains monitored URLs and may contain alerting configuration.

### Restore

<!-- coverage:restore -->

Restoring replaces both the database and configuration:

```bash
./restore.sh ./backups/gatus-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
```

The script validates the archive and takes a safety backup of the current state
first. Afterward, check `/health`, sign in, and confirm that endpoint names,
history, and announcements are the ones you expected.

### Update

<!-- coverage:update -->

Back up the instance, read the upstream release notes, change `GATUS_VERSION` in
`.env`, then recreate the container:

```bash
docker compose pull
docker compose up -d
docker compose logs --tail=100 gatus
```

Check `/health` and wait for every endpoint to produce a fresh result. Gatus
applies SQLite schema changes on startup; an HTTP response alone does not prove
that existing history remains readable.

### Rollback

<!-- coverage:rollback -->

Put the previous `GATUS_VERSION` back in `.env` and run `docker compose pull &&
docker compose up -d`. If the old image cannot read a database changed by the
new release, keep the old version selected and restore the pre-update archive.

### Complete removal

<!-- coverage:removal -->

`docker compose down` stops Gatus and keeps the database. To remove everything:

```bash
docker compose down
docker volume rm gatus-data
rm -rf ~/services/gatus
```

Sources: [official Docker usage](https://github.com/TwiN/gatus/blob/v5.36.0/README.md#docker),
[configuration reference](https://github.com/TwiN/gatus/blob/v5.36.0/README.md#configuration),
[storage](https://github.com/TwiN/gatus/blob/v5.36.0/README.md#storage), and
[security](https://github.com/TwiN/gatus/blob/v5.36.0/README.md#security).
