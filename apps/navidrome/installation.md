### 1. Check your Ubuntu or Debian server

This recipe needs 1 CPU core, 256 MB of RAM, and 2 GB of disk for the server
itself; 512 MB of RAM is recommended. This is a conservative estimate for the
recipe: upstream publishes no formal minimum. Count storage for the music
separately, plus a few percent for the artwork cache. You need Ubuntu 22.04+ or
Debian 12+ with Docker Engine and Docker Compose v2.24+.

```bash
docker --version
docker compose version
```

### 2. Prepare the music library

Navidrome reads tags, not file names, so filled-in `Artist`, `Album`, `Title`,
and track number matter most. The directory layout is up to you, but
artist/album is the most convenient:

```text
/srv/music/Artist Name/Album Name (2019)/01 Track.mp3
/srv/music/Artist Name/Album Name (2019)/cover.jpg
```

Navidrome takes artwork from the tag or from a `cover.jpg`, `folder.jpg`, or
`front.jpg` file next to the tracks. MP3, FLAC, OGG, Opus, M4A, WavPack, and
other formats understood by the bundled ffmpeg are supported.

### 3. Prepare the files and variables

```bash
mkdir -p ~/services/navidrome
cd ~/services/navidrome
cp .env.example .env
chmod 600 .env
sed -i "s|^NAVIDROME_MUSIC_LOCATION=.*|NAVIDROME_MUSIC_LOCATION=/srv/music|" .env
```

`NAVIDROME_VERSION` pins the image; `NAVIDROME_PORT` sets the local port;
`NAVIDROME_MUSIC_LOCATION` is the music directory, mounted read-only;
`NAVIDROME_DATA_VOLUME` is the volume with the database, artwork, and listening
history; `NAVIDROME_SCAN_INTERVAL` controls automatic scans;
`NAVIDROME_LOG_LEVEL` and `NAVIDROME_SESSION_TIMEOUT` cover logging and session
lifetime; `NAVIDROME_BASE_URL` is only needed when the service is published
under a subpath; `NAVIDROME_INSIGHTS` controls anonymous usage statistics and is
off by default; `TZ` sets the time zone.

### 4. Create the administrator

The administrator form has no password: whoever opens it first owns the server.
Run the first start over localhost or an SSH tunnel.

```bash
docker compose pull
docker compose up -d
docker compose ps
ssh -L 4533:127.0.0.1:4533 user@server.example
```

Open `http://localhost:4533` and set a username and password. The first scan
starts right after; the container log shows how many tracks were imported:

```bash
docker compose logs --tail=50 navidrome | grep -i scanner
```

The administrator creates the other users under Users. Mobile and desktop
clients are third-party: they connect to the same address through the Subsonic
API.

### Running on a VPS

<!-- coverage:deployment-vps -->

On a VPS keep the `127.0.0.1` bind, block port 4533 from outside, and publish the
service only through an HTTPS reverse proxy. Check the state and the API:

```bash
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:4533/ping
curl --fail "http://127.0.0.1:4533/rest/ping?v=1.16.1&c=check&f=json"
```

The second request answers with an authentication error — that is expected: it
confirms the Subsonic API is serving and reports the server version.

### Access from a local network

<!-- coverage:deployment-lan -->

Without TLS use an SSH tunnel or a VPN. If the reverse proxy runs on another host
in a trusted LAN, replace `127.0.0.1` in `compose.yaml` with the server's LAN
address and restrict the port to the proxy address in the firewall. Do not
publish Navidrome on `0.0.0.0` without restrictions: the Subsonic API sends
credentials with every request.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Replace `music.example.com` with your single domain in the file you pick from
`proxy/`. `proxy/Caddyfile` obtains a certificate automatically;
`proxy/nginx.conf` expects a Certbot certificate; `proxy/traefik.yaml` uses the
`letsencrypt` resolver. For Traefik in a container, replace `127.0.0.1` with a
host gateway it can reach.

The Nginx sample disables response buffering: without it, seeking inside a track
stutters. If the service is published below the domain root, set the same
subpath in `NAVIDROME_BASE_URL`, otherwise the web interface cannot find its own
files.

```bash
curl --fail https://music.example.com/ping
```

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops the container, archives the `/data` volume, and starts it again.
Stopping is required: the SQLite database copies consistently only from a
stopped server. The archive holds users, playlists, ratings, listening history,
and the artwork cache.

The music is not in the archive: those are your own files and need their own
copy.

Navidrome also has its own mechanism — `docker compose exec navidrome
/app/navidrome backup create --datafolder /data` snapshots the database without
stopping the server. It is handy before an update, and it ends up inside the
copy that `backup.sh` makes.

### Restore

<!-- coverage:restore -->

Restoring replaces the contents of `/data` with the selected archive:

```bash
./restore.sh ./backups/navidrome-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
curl --fail http://127.0.0.1:4533/ping
```

Before replacing anything the script takes a safety copy of the current data. The
music is untouched, but the paths in the restored database must match the
current `/music` mount, otherwise tracks are marked as missing until the next
scan.

### Update

<!-- coverage:update -->

Take a backup and read the release notes. Change only the pinned
`NAVIDROME_VERSION`, then run:

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 navidrome
```

Database migrations run the first time a new version starts. Larger updates
sometimes require a full library rescan; the release notes say so when they do.

### Rollback

<!-- coverage:rollback -->

Downgrades are not supported: after a migration the older image cannot open the
database. Restore the pinned `NAVIDROME_VERSION` in `.env` and restore the
archive taken before the update:

```bash
docker compose pull
./restore.sh ./backups/navidrome-before-update.tar.gz
docker compose up -d
```

Ratings and listening history created after the update are not in that archive.

### Stopping and complete removal

<!-- coverage:removal -->

`docker compose down` removes the container but keeps the database. Complete,
irreversible removal after verifying a backup:

```bash
docker compose down
docker volume rm navidrome-data
rm -rf ~/services/navidrome
```

The `NAVIDROME_MUSIC_LOCATION` directory stays untouched: the recipe mounts it
read-only and never deletes from it.

Sources: [Docker installation](https://www.navidrome.org/docs/installation/docker/),
[configuration options](https://www.navidrome.org/docs/usage/configuration/options/),
[artwork and tags](https://www.navidrome.org/docs/usage/artwork/),
[backup and restore](https://www.navidrome.org/docs/usage/admin/backup/),
[anonymous statistics](https://www.navidrome.org/docs/usage/admin/insights/),
and [security recommendations](https://www.navidrome.org/docs/usage/admin/security/).
