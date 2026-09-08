### 1. Check the Ubuntu or Debian server

Minimum: 1 CPU, 256 MB RAM, and 2 GB of disk. 512 MB RAM is recommended — usage
grows with the cache, the query log, and the number of blocklists. You need
Ubuntu 22.04+ or Debian 12+ with Docker Engine and Docker Compose v2.24+. No
separate database is required.

```bash
docker --version
docker compose version
```

### 2. Free up port 53

On Ubuntu and Debian port 53 is almost always held by `systemd-resolved`. Check:

```bash
sudo ss -lunp | grep ':53 '
```

If the output mentions `systemd-resolve`, disable its stub listener but keep the
service running — otherwise the server itself loses name resolution:

```bash
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nDNSStubListener=no\n' | sudo tee /etc/systemd/resolved.conf.d/adguardhome.conf
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved
sudo ss -lunp | grep ':53 ' || echo "port 53 is free"
```

Pointing at `/run/systemd/resolve/resolv.conf` leaves the host with working
upstream servers. Do not point `/etc/resolv.conf` at AdGuard Home itself before
it is running, or the server will be left without DNS.

### 3. Prepare the files and variables

Put `compose.yaml`, `.env.example`, `backup.sh`, `restore.sh`, and the `proxy`
directory into a dedicated directory:

```bash
mkdir -p ~/services/adguard-home
cd ~/services/adguard-home
cp .env.example .env
chmod 600 .env
```

`.env` defines:

- `ADGUARD_VERSION` — the pinned image tag, including the `v` prefix;
- `ADGUARD_DNS_BIND` — the address the DNS ports are published on, `127.0.0.1` by default;
- `ADGUARD_DNS_PORT` — the published DNS port, normally `53`;
- `ADGUARD_WEB_PORT` — the local control panel port, `3000` by default;
- `ADGUARD_CONF_VOLUME` — the volume holding `AdGuardHome.yaml`: users, upstreams, rules;
- `ADGUARD_WORK_VOLUME` — the volume holding statistics, the query log, and downloaded blocklists;
- `TZ` — the time zone, which drives charts and schedules.

All user data lives in those two volumes only. Nothing is stored in the recipe
directory.

### 4. Start the container on a VPS

<!-- coverage:deployment-vps -->

```bash
docker compose pull
docker compose up -d
docker compose ps
```

With the defaults, no port faces the outside world: both DNS and the panel are
bound to `127.0.0.1`. On a VPS it should stay that way — grant resolver access
over a VPN (WireGuard, Tailscale) by setting `ADGUARD_DNS_BIND` to the VPN
interface address. Never open port 53 on a public address: the server would
become an open resolver and be abused for DNS amplification.

### 5. Complete the setup wizard

The panel is local only, so forward the port over SSH:

```bash
ssh -L 3000:127.0.0.1:3000 user@server.example
```

Open `http://localhost:3000`. In the wizard keep the web interface on port
`3000` and DNS on port `53` — those match the in-container ports from
`compose.yaml`. Choosing different ones makes the healthcheck and the port
mapping disagree with the configuration. Set an administrator name and a long
password, and store it in a password manager.

After the wizard, verify the server works:

```bash
docker compose exec adguard-home nslookup example.org 127.0.0.1
```

### Local network

<!-- coverage:deployment-lan -->

For the devices on your network to use filtering, DNS must listen on the LAN
interface. Set the server address in `.env` and recreate the container:

```bash
sed -i 's/^ADGUARD_DNS_BIND=.*/ADGUARD_DNS_BIND=192.168.1.10/' .env
docker compose up -d
```

Do not use `0.0.0.0`: on a VPS it exposes the resolver to the whole internet.
Close port 53 on the external interface in the firewall and allow it from the
local subnet only:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 53 proto udp
sudo ufw allow from 192.168.1.0/24 to any port 53 proto tcp
```

Then set the server address as the DNS server in your router, which enables
filtering for every device at once. The control panel stays on `127.0.0.1`.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

A reverse proxy publishes the control panel only: DNS speaks its own protocol
and does not pass through an HTTP proxy. Ready-made samples live in
`proxy/Caddyfile`, `proxy/nginx.conf`, and `proxy/traefik.yaml`; replace
`dns.example.com` with your domain. Caddy obtains a certificate automatically,
the Nginx sample assumes a Certbot certificate, and Traefik uses the
`letsencrypt` resolver. For Traefik in a container, replace `127.0.0.1` with a
host gateway address the container can reach.

The panel exposes the query history of the whole network, so restrict the domain
further by IP or with basic authentication on the proxy side. This recipe does
not configure AdGuard Home's own DNS-over-HTTPS: that needs port 443 published
separately and a certificate handed to the server.

### Backup

<!-- coverage:backup -->

Data lives in the `adguard-home-conf` and `adguard-home-work` volumes. The
script archives both at once — configuration restored without statistics ends up
inconsistent:

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The archive appears in `./backups`. It contains `AdGuardHome.yaml` with the
administrator login and password hash, so keep a copy off the server and in a
protected place.

### Restore

<!-- coverage:restore -->

Restoring completely replaces the contents of both volumes with the chosen
archive:

```bash
./restore.sh ./backups/adguard-home-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
```

Before unpacking, the script creates a safety copy of the current data.

### Update

<!-- coverage:update -->

Disable the built-in auto-update in the panel — the version is set by the image
tag. Create a backup, read the release notes, change `ADGUARD_VERSION` in `.env`
(keep the `v` prefix), then run:

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 adguard-home
```

### Rollback

<!-- coverage:rollback -->

Restore the previous `ADGUARD_VERSION` in `.env` and run `docker compose pull`
and `docker compose up -d`. AdGuard Home keeps its settings in
`AdGuardHome.yaml` and rewrites the file into its own version's format on start,
so after a rollback the older binary may fail to read the upgraded config. In
that case restore the archive made before the update:

```bash
./restore.sh ./backups/adguard-home-YYYYMMDDTHHMMSSZ.tar.gz
```

The application has no separate database; migrations are limited to that file.

### Removal

<!-- coverage:removal -->

Keep the data: `docker compose down`. Remove the container and all data
irreversibly:

```bash
docker compose down
docker volume rm adguard-home-conf adguard-home-work
rm -rf ~/services/adguard-home
```

Remember to restore the previous DNS server in the router and on your devices,
or the network will be left without name resolution. If you disabled the stub
listener, bring it back:

```bash
sudo rm /etc/systemd/resolved.conf.d/adguardhome.conf
sudo systemctl restart systemd-resolved
```

Sources: [Docker installation](https://adguard-dns.io/kb/adguard-home/getting-started/#docker),
[post-install setup](https://adguard-dns.io/kb/adguard-home/getting-started/#post-install),
and [configuration](https://adguard-dns.io/kb/adguard-home/configuration/).
