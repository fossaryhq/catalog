### 1. Check your Ubuntu or Debian server

For this recipe budget at least 2 CPU cores, 1 GB of RAM, and 5 GB of disk for
the server itself; 4 GB of RAM is recommended. This is a conservative estimate
for the recipe: upstream publishes no formal minimum, because the load depends
entirely on how you use it. Direct play costs almost nothing, while transcoding
a single 4K stream can saturate the CPU. Count storage for the media library
separately. You need Ubuntu 22.04+ or Debian 12+ with Docker Engine and Docker
Compose v2.24+.

```bash
docker --version
docker compose version
nproc && free -m
```

### 2. Lay out the library the way Jellyfin expects

Artwork and descriptions are fetched automatically only when files follow the
upstream naming rules: one directory per movie, with the year in parentheses.

```text
/srv/media/Movies/Sintel (2010)/Sintel (2010).mkv
/srv/media/Movies/Tears of Steel (2012)/Tears of Steel (2012).mkv
/srv/media/Shows/Show Name (2021)/Season 01/Show Name S01E01.mkv
```

### 3. Prepare the files and variables

Put the recipe files in their own directory and create a private `.env`:

```bash
mkdir -p ~/services/jellyfin
cd ~/services/jellyfin
cp .env.example .env
chmod 600 .env
sed -i "s|^JELLYFIN_MEDIA_LOCATION=.*|JELLYFIN_MEDIA_LOCATION=/srv/media|" .env
```

`JELLYFIN_VERSION` pins the image; `JELLYFIN_PORT` sets the local port;
`JELLYFIN_PUBLISHED_URL` is the external address the server announces to
clients; `JELLYFIN_MEDIA_LOCATION` is the media directory, mounted read-only;
`JELLYFIN_CONFIG_VOLUME` and `JELLYFIN_CACHE_VOLUME` name the Docker volumes;
`TZ` sets the time zone.

Settings, the database, metadata, and accounts live in the `/config` volume.
`/cache` holds thumbnails and transcoding temporaries — that volume is rebuilt
by a rescan and does not belong in a backup.

### 4. Complete the setup wizard

The wizard is not password protected: until an administrator exists, whoever
opens the port owns the server. Run the first start over localhost or an SSH
tunnel.

```bash
docker compose pull
docker compose up -d
docker compose ps
ssh -L 8096:127.0.0.1:8096 user@server.example
```

Open `http://localhost:8096`, choose the interface language, create the
administrator, and add a library pointing at `/media/Movies` — that is the path
inside the container, not on the host. After the scan finishes, check that
artwork was fetched.

### Running on a VPS

<!-- coverage:deployment-vps -->

On a VPS keep the `127.0.0.1` bind, block port 8096 from outside, and publish the
service only through an HTTPS reverse proxy. Check the state and the API:

```bash
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:8096/health
```

Keep in mind that a shared vCPU is almost always too weak for transcoding. Store
files in formats your clients play directly, and watch Dashboard → Playback to
see when the server starts transcoding.

### Access from a local network

<!-- coverage:deployment-lan -->

Without TLS use an SSH tunnel or a VPN. If the reverse proxy runs on another host
in a trusted LAN, replace `127.0.0.1` in `compose.yaml` with the server's LAN
address and restrict the port to the proxy address in the firewall.

Client autodiscovery uses UDP port 7359: to enable it, add `- "7359:7359/udp"` to
the `ports` section. DLNA requires `network_mode: host` and is deliberately not
enabled in this recipe — it gives up the container's network isolation, so turn
it on only inside a trusted network.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Replace `media.example.com` with your single domain in the file you pick from
`proxy/`, and set the same address in `JELLYFIN_PUBLISHED_URL`.
`proxy/Caddyfile` obtains a certificate automatically; `proxy/nginx.conf` expects
a Certbot certificate; `proxy/traefik.yaml` uses the `letsencrypt` resolver. For
Traefik in a container, replace `127.0.0.1` with a host gateway it can reach.

All samples disable response buffering and pass WebSocket connections through:
without that, seeking breaks and clients lose contact with the server. To see
real client addresses in the activity log, add the proxy address under
Dashboard → Networking → Known proxies.

```bash
curl --fail https://media.example.com/health
```

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops the container, archives the whole `/config` volume, and starts
it again. Stopping is required: SQLite databases copy consistently only from a
stopped server. The archive holds settings, users, metadata, images, and watch
history.

The media library is not in the archive: those are your own files and need their
own copy. The cache is not saved either — a rescan rebuilds it.

Jellyfin 10.11 also has its own mechanism: Dashboard → Backups → Create Backup
writes an archive to `/config/data/backups` without stopping the server. It is
handy before an update, and it ends up inside the copy that `backup.sh` makes.

### Restore

<!-- coverage:restore -->

Restoring replaces the contents of `/config` with the selected archive:

```bash
./restore.sh ./backups/jellyfin-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
curl --fail http://127.0.0.1:8096/health
```

Before replacing anything the script takes a safety copy of the current data and
clears the cache: thumbnails and transcodes from the previous database become
invalid after the swap. The media library is untouched, but the library paths in
the restored database must match the current `/media` mount.

### Update

<!-- coverage:update -->

Take a backup and read the release notes. Change only the pinned
`JELLYFIN_VERSION`, then run:

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 jellyfin
```

Upgrade one version at a time and do not skip major releases: database
migrations assume an upgrade from the previous version.

### Rollback

<!-- coverage:rollback -->

Jellyfin has no downgrade mechanism. Migrations are applied the first time a new
image starts, after which the old version can no longer open the data. The only
way back is to restore the pinned `JELLYFIN_VERSION` in `.env` and restore the
archive taken before the update:

```bash
docker compose pull
./restore.sh ./backups/jellyfin-before-update.tar.gz
docker compose up -d
```

Watch history and metadata edits made after the update are not in that archive.

### Stopping and complete removal

<!-- coverage:removal -->

`docker compose down` removes the container but keeps the settings. Complete,
irreversible removal after verifying a backup:

```bash
docker compose down
docker volume rm jellyfin-config jellyfin-cache
rm -rf ~/services/jellyfin
```

The `JELLYFIN_MEDIA_LOCATION` directory stays untouched: the recipe mounts it
read-only and never deletes from it.

Sources: [container installation](https://jellyfin.org/docs/general/installation/container/),
[quick start](https://jellyfin.org/docs/general/quick-start),
[movie naming](https://jellyfin.org/docs/general/server/media/movies),
[backup and restore](https://jellyfin.org/docs/general/administration/backup-and-restore),
and [reverse proxy](https://jellyfin.org/docs/general/post-install/networking/reverse-proxy/).
