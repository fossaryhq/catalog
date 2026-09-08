### 1. Check the server

You need Ubuntu 22.04+ or Debian 12+ with Docker Engine and Docker Compose
v2.24+. Budget 1 CPU, 512 MB of RAM, and 2 GB of local disk; 1 GB of RAM is more
comfortable. There is no separate database to plan for.

Keep the data on a local filesystem or a Docker volume. Upstream advises against
NFS, and SQLite over NFS corrupts in ways that only show up later.

```bash
docker --version
docker compose version
```

### 2. Prepare the files and variables

Put `compose.yaml`, `.env.example`, `backup.sh`, `restore.sh`, and `proxy/` in a
directory of their own:

```bash
mkdir -p ~/services/uptime-kuma
cd ~/services/uptime-kuma
cp .env.example .env
chmod 600 .env
```

`.env` holds four values: the pinned `UPTIME_KUMA_VERSION`, the local
`UPTIME_KUMA_PORT`, the `UPTIME_KUMA_DATA_VOLUME` name, and `TZ`.

### 3. Start the container on a VPS

<!-- coverage:deployment-vps -->

```bash
docker compose pull
docker compose up -d
docker compose ps
```

The image carries its own healthcheck. On a first run the container can sit in
`starting` for a couple of minutes while it lays out the database — that is
normal. The port is bound to `127.0.0.1`, so nothing is reachable from outside
yet.

### 4. Finish the setup over SSH

```bash
ssh -L 3001:127.0.0.1:3001 user@server.example
```

Open `http://localhost:3001`, create the administrator, and put the password in a
password manager. There is no recovery flow if you lose it.

### Local network

<!-- coverage:deployment-lan -->

Without a reverse proxy, keep the localhost bind and reach the interface through
an SSH tunnel. If you trust the LAN, replace `127.0.0.1` in `compose.yaml` with
the server's own LAN address — `192.168.1.10`, say — never `0.0.0.0`, and block
port 3001 on the external interface with a firewall.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

For a reverse proxy on the host, `proxy/Caddyfile`, `proxy/nginx.conf`, and
`proxy/traefik.yaml` are ready to use. Replace `status.example.com` with your
domain. Caddy gets a certificate on its own, the Nginx example expects one from
Certbot, and Traefik uses the `letsencrypt` resolver.

Two things matter here. Turn on **Trust Proxy** in Uptime Kuma, or every check
will be attributed to the proxy's address. And keep the WebSocket upgrade: all
three examples forward it already, and without it the dashboard loads once and
then stops updating. For Traefik in a container, replace `127.0.0.1` with a host
gateway address that container can actually reach.

### Backup

<!-- coverage:backup -->

Everything lives in the `uptime-kuma-data` volume:

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops the container, writes an archive into `./backups`, and starts it
again. It stops the container on purpose: copying a live SQLite database gives
you an archive that restores into a corrupt one. Keep a second copy off this
server.

### Restore

<!-- coverage:restore -->

Restoring replaces the volume contents with the archive you name:

```bash
./restore.sh ./backups/uptime-kuma-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
```

The script takes a safety copy of the current data first, so a restore from the
wrong archive is recoverable.

### Update

<!-- coverage:update -->

Back up, read the release notes, change `UPTIME_KUMA_VERSION` in `.env`, then:

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 uptime-kuma
```

### Rollback

<!-- coverage:rollback -->

Put the previous `UPTIME_KUMA_VERSION` back in `.env` and run `docker compose
pull && docker compose up -d`.

If the new release migrated the database, the old image will not read the new
schema: return to the old version first, then restore the pre-update archive with
`restore.sh`. Read the upstream release notes before crossing a major version in
either direction.

### Complete removal

<!-- coverage:removal -->

`docker compose down` stops everything and keeps the data. To remove the
container and the data for good:

```bash
docker compose down
docker volume rm uptime-kuma-data
rm -rf ~/services/uptime-kuma
```

Sources: [official installation](https://github.com/louislam/uptime-kuma#how-to-install)
and [update guide](https://github.com/louislam/uptime-kuma/wiki/%F0%9F%86%99-How-to-Update).
