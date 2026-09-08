### The container will not start: address already in use on port 53

The port is held by `systemd-resolved` or another resolver:

```bash
sudo ss -lunp | grep ':53 '
docker compose logs --tail=100 adguard-home
```

Disable the stub listener as described in step 2 of the guide. If another
container holds the port, find it with `docker ps` — two DNS servers cannot
share one address.

### The container never becomes healthy

The healthcheck queries the panel on port 3000 inside the container:

```bash
docker compose ps
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q adguard-home)"
```

The most common cause is a different web interface port chosen in the setup
wizard. Set it back to 3000 in `AdGuardHome.yaml` (the `http.address` key), or
adjust the healthcheck and the port mapping in `compose.yaml` to match.

### Devices on the network cannot reach DNS

Check which address the port is published on:

```bash
docker compose port adguard-home 53/udp
```

An answer starting with `127.0.0.1` means `ADGUARD_DNS_BIND` was never changed.
Set the server's LAN interface address and run `docker compose up -d`. Then test
from a client:

```bash
nslookup example.org 192.168.1.10
```

An empty answer while the server is running usually means the firewall: port 53
is needed over both UDP and TCP.

### Ads still show up

Make sure the device really goes through the server: its domains should appear
in the query log. Many browsers and phones use their own DNS-over-HTTPS,
bypassing the system settings — turn it off in the browser or block it with a
router rule. Ads served from the same domain as the content (a social media
feed, for example) cannot be removed by DNS filtering at all.

### A site broke after enabling a filter

Find the domain in the query log, open the entry, and click unblock — an
`@@||domain^` rule goes into your custom exceptions. You can also check which
rule matched without making a query:

```bash
curl -u admin:password 'http://127.0.0.1:3000/control/filtering/check_host?name=example.org'
```

### After an update the panel asks to run the wizard again

The container did not find its configuration — nearly always a different volume:

```bash
docker volume inspect adguard-home-conf
docker compose config
```

Do not run the wizard again before you check the data path: a fresh install
overwrites `AdGuardHome.yaml`. If the volume is gone, restore an archive with
`./restore.sh`.

### The administrator password is lost

There is no reset command: stop the container, open `AdGuardHome.yaml` in the
`adguard-home-conf` volume, replace the hash in the `users` block with a new
bcrypt hash, and start the container. Make a backup before editing.
