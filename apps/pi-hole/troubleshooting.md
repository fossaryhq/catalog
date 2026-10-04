### Port 53 is already in use

Check the exact listening address, not just the port:

```bash
sudo ss -luntp | grep ':53 '
docker compose logs --tail=100 pi-hole
```

`127.0.0.53` used by `systemd-resolved` is distinct from the default
`127.0.0.1` bind. If a service holds `127.0.0.1:53` or all interfaces, choose
a specific free LAN/VPN address or reconfigure the conflicting service.
Avoid changing the host resolver until a working alternative is configured.

### The container is unhealthy

The official image's healthcheck makes a DNS request to its own FTL process:

```bash
docker compose ps
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q pi-hole)"
docker compose logs --tail=150 pi-hole
```

If the logs show a corrupted database, restore a known good volume archive.
If they show a permissions or disk error, inspect the volume and free space.

### A LAN device cannot resolve names

```bash
docker compose port pi-hole 53/udp
nslookup pi.hole 192.168.1.10
```

If Compose reports `127.0.0.1`, set `PIHOLE_DNS_BIND` to the actual LAN address
and recreate the container. Permit both TCP and UDP 53 in the LAN firewall.
Make sure the router hands out the same server address over DHCP.

### Ads still appear, or a site breaks

Check the query log: if the client's requests are absent, it may use its own
DNS-over-HTTPS or a different DNS server. Network filtering cannot remove
content served from the same domain as the page itself. For a broken site,
find its blocked domain in Query Log and add only that domain to the allowlist.
Avoid disabling all blocking to fix one false positive.

### The web password does not work

Verify that `.env` contains the intended `PIHOLE_WEB_PASSWORD` and recreate the
container with `docker compose up -d`. The `FTLCONF_webserver_api_password`
environment setting controls the password on every start. Avoid pasting a
password into shell history or posting `docker inspect` output publicly.

### A restored instance looks new

Check that `PIHOLE_VOLUME` names the same volume as the backup and that the
archive contains `pihole.toml` and `gravity.db`:

```bash
docker compose config
docker volume inspect pi-hole-data
tar -tzf ./backups/pi-hole-YYYYMMDDTHHMMSS.NNNNNNNNNZ.tar.gz | grep -E 'pihole.toml|gravity.db'
```

Do not create new lists before finding the correct volume or restoring the
pre-update archive.
