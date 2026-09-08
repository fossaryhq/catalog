### 1. Check your Ubuntu or Debian server

This recipe needs 1 CPU core, 256 MB of RAM, and 2 GB of disk for the node
itself; 512 MB of RAM is recommended. This is a conservative estimate for the
recipe: upstream publishes no formal minimum, and memory use grows with the
number of files in the index. Count storage for the files separately: Syncthing
keeps a full copy of every synchronised folder. You need Ubuntu 22.04+ or
Debian 12+ with Docker Engine and Docker Compose v2.24+.

```bash
docker --version
docker compose version
```

### 2. Prepare the files and variables

```bash
mkdir -p ~/services/syncthing
cd ~/services/syncthing
cp .env.example .env
chmod 600 .env
sudo mkdir -p /srv/syncthing
sudo chown 1000:1000 /srv/syncthing
sed -i "s|^SYNCTHING_DATA_LOCATION=.*|SYNCTHING_DATA_LOCATION=/srv/syncthing|" .env
```

`SYNCTHING_VERSION` pins the image; `SYNCTHING_DEVICE_NAME` is the name other
nodes see; `SYNCTHING_GUI_PORT` publishes the web interface on localhost only;
`SYNCTHING_SYNC_PORT` and `SYNCTHING_DISCOVERY_PORT` carry the data exchange and
local discovery; `SYNCTHING_DATA_LOCATION` is the directory with the
synchronised files; `SYNCTHING_CONFIG_VOLUME` is the volume with the
configuration, device keys, and index database; `SYNCTHING_UID` and
`SYNCTHING_GID` set the file owner; `TZ` sets the time zone.

Directory ownership matters: the container runs as `1000:1000`, and without the
`chown` Syncthing cannot write to `/srv/syncthing`.

### 3. Start the node and set a password

```bash
docker compose pull
docker compose up -d
docker compose ps
ssh -L 8384:127.0.0.1:8384 user@server.example
```

Open `http://localhost:8384`. The web interface has no password at first, so go
to Actions → Settings → GUI right away and set a user and password — the
interface must not be published without one.

The device ID (Actions → Show ID) is what nodes exchange when they meet. On the
second device add the server by that ID, accept the request on the server, then
pick a folder and choose which device to share it with.

### Running on a VPS

<!-- coverage:deployment-vps -->

On a VPS the web interface stays on `127.0.0.1`, but the sync port must be
reachable from outside — otherwise devices connect only through public relays
and throughput drops several times over. Open it in the firewall:

```bash
sudo ufw allow 22000/tcp
sudo ufw allow 22000/udp
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:8384/rest/noauth/health
```

Port 21027/udp is only for discovering devices on the same local network; there
is no reason to open it on a VPS.

### Access from a local network

<!-- coverage:deployment-lan -->

Inside a trusted LAN the web interface is most conveniently reached through an
SSH tunnel or a VPN. If the reverse proxy runs on another host in the network,
replace `127.0.0.1` in `compose.yaml` with the server's LAN address and restrict
the port to the proxy address in the firewall.

Port 21027/udp enables automatic discovery: devices on the same network find
each other without typing addresses. The data exchange still goes over port
22000.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Only the web interface goes through the reverse proxy. The sync port speaks its
own protocol and does not pass through an HTTP proxy: it stays on 22000.

Replace `sync.example.com` with your single domain in the file you pick from
`proxy/`. `proxy/Caddyfile` obtains a certificate automatically;
`proxy/nginx.conf` expects a Certbot certificate; `proxy/traefik.yaml` uses the
`letsencrypt` resolver. For Traefik in a container, replace `127.0.0.1` with a
host gateway it can reach.

Set a password under Settings → GUI before exposing the interface. The Nginx
sample raises `proxy_read_timeout`: the interface holds long event requests, and
a short timeout breaks the connection.

```bash
curl --fail https://sync.example.com/rest/noauth/health
```

### Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops the container, archives the configuration volume, and starts it
again. The archive holds the device's private key, its identifier, the folder
and device lists, and the index database.

The synchronised files are not in the archive, deliberately: every node already
holds a copy. What matters more is this: Syncthing is not a backup. A deletion
propagates to every device as fast as any other change. Enable File Versioning
in the folder settings to survive an accidental deletion, and use a dedicated
tool for real backups.

The archive contains a private key: encrypt it before it leaves the server.

### Restore

<!-- coverage:restore -->

Restoring brings back the previous device identifier, so the other nodes keep
working without being re-added:

```bash
./restore.sh ./backups/syncthing-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
curl --fail http://127.0.0.1:8384/rest/noauth/health
```

Before replacing anything the script takes a safety copy of the current
configuration. If the data directory is empty, the node downloads the files
again from the other devices; if the files are in place, Syncthing rescans them
and finds the match.

Never run two copies of the same configuration at once: two nodes with the same
identifier conflict inside the cluster.

### Update

<!-- coverage:update -->

Take a backup and read the release notes. Change only the pinned
`SYNCTHING_VERSION`, then run:

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 syncthing
```

Nodes of different versions work together, but protocol compatibility is not
unlimited: across major versions, update all devices at roughly the same time.

### Rollback

<!-- coverage:rollback -->

The index database format changes between major versions and does not migrate
downwards. Restore the pinned `SYNCTHING_VERSION` in `.env` and restore the
archive taken before the update:

```bash
docker compose pull
./restore.sh ./backups/syncthing-before-update.tar.gz
docker compose up -d
```

The files themselves are not at risk: at worst the node rebuilds its index.

### Stopping and complete removal

<!-- coverage:removal -->

`docker compose down` removes the container but keeps the configuration and
keys. Complete, irreversible removal after verifying a backup:

```bash
docker compose down
docker volume rm syncthing-config
rm -rf ~/services/syncthing
```

The `SYNCTHING_DATA_LOCATION` directory stays where it is: the recipe never
deletes it. After the node is gone, the other devices show it as disconnected
until you remove it from their settings.

Sources: [getting started](https://docs.syncthing.net/intro/getting-started.html),
[configuration](https://docs.syncthing.net/users/config.html),
[firewall and ports](https://docs.syncthing.net/users/firewall.html),
[file versioning](https://docs.syncthing.net/users/versioning.html),
[reverse proxy](https://docs.syncthing.net/users/reverseproxy.html),
and [security](https://docs.syncthing.net/users/security.html).
