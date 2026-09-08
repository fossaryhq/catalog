### Behind a reverse proxy the panel returns 400: Bad Request

Home Assistant does not trust the `X-Forwarded-For` header until you allow it
explicitly. `configuration.yaml` needs an `http` block:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.18.0.1
```

The address in `trusted_proxies` is the address the request arrives from inside
the container, which is almost never `127.0.0.1`. For a proxy on the host it is
the Docker network gateway, as in the example above; for a proxy in a container
it is that container's address on the shared network. Take the real value from
the log rather than guessing it:

```bash
docker compose logs --tail=50 home-assistant | grep -i forwarded
```

Do not widen the list to the whole subnet: anyone who gets into it can spoof the
client address.

### The panel loads but stays blank

The interface receives data over WebSocket. If the proxy does not pass the
upgrade through, the page loads and hangs. Nginx needs these headers:

```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

Caddy and Traefik do it themselves. To confirm the proxy is at fault, reach
`127.0.0.1:8123` directly through an SSH tunnel.

### The container never becomes healthy

```bash
docker compose ps
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q home-assistant)"
docker compose logs --tail=100 home-assistant
```

The first start takes longer than later ones: the healthcheck `start_period` is
120 seconds. If the container restarts in a loop, an error in
`configuration.yaml` is almost always the cause:

```bash
docker compose exec home-assistant python -m homeassistant --script check_config -c /config
```

When the core cannot read the configuration it comes up in recovery mode: the
panel works, but there are no integrations and no automations. That shows in the
`state` field of the `/api/config` response and in the interface header.

### Devices are not discovered automatically

That is expected: the container runs on an isolated Compose network and never
receives the mDNS, SSDP, and DHCP broadcasts discovery is built on. Add
integrations by hand and enter the device IP address. If you need automatic
discovery, you have to switch to `network_mode: host` — that gives the container
access to the host's entire network, and the recipe deliberately leaves it out.

### The owner password is lost

The image ships a script for managing accounts. Stop the container so the
database is not edited under a running server, then change the password:

```bash
docker compose stop home-assistant
docker compose run --rm home-assistant python -m homeassistant --script auth --config /config list
docker compose run --rm home-assistant python -m homeassistant --script auth --config /config change_password smoke NewPassword
docker compose start home-assistant
```

Make a backup first. Do not delete the `.storage/auth*` files: that also removes
every user, every companion app token, and every device link.

### The history database grows to tens of gigabytes

By default Home Assistant keeps 10 days of history, but with many sensors the
`home-assistant_v2.db` file still grows quickly. Limit the retention and exclude
noisy entities in `configuration.yaml`:

```yaml
recorder:
  purge_keep_days: 7
  exclude:
    domains:
      - device_tracker
      - sun
```

The file does not shrink immediately after the edit: space is reclaimed by the
`recorder.purge` action with `repack: true`.

### An integration broke after an update

Check the Backward-incompatible changes section of your release notes:
integrations move and change their settings format. The quick fix is to restore
the previous tag in `.env` and run `docker compose up -d`. If the older version
refuses to start because the `.storage` migration already happened, restore the
archive created before the update:

```bash
./restore.sh ./backups/home-assistant-YYYYMMDDTHHMMSSZ.tar.gz
```

### Automations fire at the wrong time

Check both time zones: the container `TZ` from `.env` and the application's own
zone under "Settings" → "System" → "General". Sunset and sunrise automations also
depend on the coordinates set during onboarding.

```bash
docker compose exec home-assistant date
```
