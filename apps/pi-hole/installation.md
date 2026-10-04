### 1. Prepare the server

Use Ubuntu 22.04+ or Debian 12+ with Docker Engine and Docker Compose v2.24+.
Allow at least one CPU core, 512 MB RAM, and 2 GB of disk; 1 GB RAM and 4 GB
of disk leave room for retained query history and several blocklists.
No separate database is needed. Check the tools and whether anything already
uses DNS port 53:

```bash
docker --version
docker compose version
sudo ss -luntp | grep ':53 ' || true
```

`systemd-resolved` often listens on `127.0.0.53`, which does not necessarily
conflict with this recipe's `127.0.0.1` bind. Change the host resolver only if
the actual address conflicts. Do not point the host's `/etc/resolv.conf` at
Pi-hole before Pi-hole is running.

### 2. Prepare the recipe

Place `compose.yaml`, `.env.example`, `backup.sh`, `restore.sh`, and `proxy/`
in a dedicated directory, then create your private environment file:

```bash
mkdir -p ~/services/pi-hole
cd ~/services/pi-hole
cp .env.example .env
chmod 600 .env
openssl rand -hex 24
```

Replace the `PIHOLE_WEB_PASSWORD` example in `.env` with the generated value.
Never start a real instance with the sample password. The variables are:

- `PIHOLE_VERSION`: pinned official image release;
- `PIHOLE_WEB_PASSWORD`: administrator password;
- `PIHOLE_DNS_BIND`: host address for TCP and UDP DNS, initially `127.0.0.1`;
- `PIHOLE_DNS_PORT`: host DNS port, normally `53`;
- `PIHOLE_WEB_PORT`: host-only admin port, initially `8080`;
- `PIHOLE_VOLUME`: Docker volume holding all persistent Pi-hole data;
- `TZ`: IANA time zone for charts and schedules.

The Compose file sets `FTLCONF_dns_listeningMode=ALL` because DNS arrives
through Docker's bridge. It does not publish Pi-hole's DHCP (67/udp), NTP
(123/udp), or self-signed HTTPS (443/tcp) listeners.

### 3. Start on a VPS

<!-- coverage:deployment-vps -->

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait
docker compose ps
```

With the defaults, DNS and the panel are reachable only from the host. On a VPS,
keep DNS on a private VPN address, such as WireGuard or Tailscale, by setting
`PIHOLE_DNS_BIND` to that interface address. Never use `0.0.0.0` or a public
address: public DNS resolvers are abused for amplification. The panel can be
accessed with an SSH tunnel:

```bash
ssh -L 8080:127.0.0.1:8080 user@server.example
```

Open `http://localhost:8080/admin/` and sign in with the password from `.env`.
The web interface is currently English-only. Test the DNS server on the host:

```bash
dig @127.0.0.1 pi.hole
```

### Trusted local network

<!-- coverage:deployment-lan -->

Set `PIHOLE_DNS_BIND` in `.env` to this server's specific LAN address, for
example `192.168.1.10`, and recreate the container:

```bash
docker compose up -d --wait
docker compose port pi-hole 53/udp
```

Permit UDP and TCP 53 only from the trusted subnet in your firewall. For UFW:

```bash
sudo ufw allow from 192.168.1.0/24 to 192.168.1.10 port 53 proto udp
sudo ufw allow from 192.168.1.0/24 to 192.168.1.10 port 53 proto tcp
```

Then set `192.168.1.10` as the DNS server in your router's DHCP settings, or
configure clients individually. Test from another device with
`nslookup pi.hole 192.168.1.10`. Do not enable Pi-hole's DHCP service with this
recipe: bridge networking does not carry the broadcasts it needs.

### Domain and HTTPS

<!-- coverage:deployment-domain-https -->

The `proxy/Caddyfile`, `proxy/nginx.conf`, and `proxy/traefik.yaml` examples
publish only the web panel; substitute your own `dns.example.com`. Caddy obtains
certificates automatically; Nginx expects a Certbot certificate; Traefik uses
the configured `letsencrypt` resolver. If Traefik runs in a container, replace
`127.0.0.1` with a host gateway address that container can reach. Keep the
Pi-hole login enabled and restrict panel access to trusted users. An HTTP proxy
does not carry ordinary DNS traffic on port 53.

### Backup

<!-- coverage:backup -->

All persistent settings, blocklists, Gravity database, and query history live
in the `pi-hole-data` Docker volume (or the name in `PIHOLE_VOLUME`). The script
stops Pi-hole briefly so its SQLite files are consistent:

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Copy the resulting `./backups/pi-hole-*.tar.gz` off the server and protect it;
it contains DNS history and configuration. The `.env` password is separate and
must be stored securely too. The web interface's Teleporter export is useful
for selected settings, but this full-volume archive is needed for a complete
restore.

### Restore

<!-- coverage:restore -->

Restoring replaces the entire `PIHOLE_VOLUME` contents. The script creates a
safety backup of the current state first:

```bash
./restore.sh ./backups/pi-hole-YYYYMMDDTHHMMSS.NNNNNNNNNZ.tar.gz
docker compose ps
```

Restore the matching `.env` separately if the password or volume name changed.

### Update

<!-- coverage:update -->

Read the [Docker release notes](https://github.com/pi-hole/docker-pi-hole/releases)
and create a backup. Change `PIHOLE_VERSION` in `.env` to a tested, dated tag;
never use `latest`. Then:

```bash
./backup.sh
docker compose pull
docker compose up -d --wait
docker compose logs --tail=100 pi-hole
```

### Rollback

<!-- coverage:rollback -->

Restore the previous pinned tag in `.env`, pull it, and recreate the container.
If the new version changed `pihole.toml` or the SQLite databases, restore the
pre-update archive too; an older image may not read newer data:

```bash
docker compose pull
docker compose up -d --wait
./restore.sh ./backups/pi-hole-YYYYMMDDTHHMMSS.NNNNNNNNNZ.tar.gz
```

The restore script first saves the current data, then replaces the volume. Check
the panel and a DNS query after the rollback.

### Stop or remove

<!-- coverage:removal -->

`docker compose down` stops and removes the container while retaining its data.
After moving the router and clients to another DNS server, permanently remove
the stored data with `docker compose down --volumes` (or remove the volume named
by `PIHOLE_VOLUME`). Keep any off-server backups you still need. Removing the
resolver while clients still point to it interrupts name resolution.

Sources: [official Docker setup](https://docs.pi-hole.net/docker/),
[Docker configuration and capabilities](https://docs.pi-hole.net/docker/configuration/),
the [hardware prerequisites](https://docs.pi-hole.net/main/prerequisites/),
and [Pi-hole v6 configuration](https://docs.pi-hole.net/ftldns/configfile/).
