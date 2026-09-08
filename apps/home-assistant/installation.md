### 1. Check the Ubuntu or Debian server

Minimum: 2 CPUs, 1 GB of RAM, and 8 GB of disk. 2 GB of RAM is recommended —
consumption grows with the number of integrations, and the history database
takes space proportional to the number of devices. You need Ubuntu 22.04+ or
Debian 12+ with Docker Engine and Docker Compose v2.24+. No separate database is
required: by default Home Assistant writes history to SQLite inside `/config`.

```bash
docker --version
docker compose version
```

### 2. Prepare the files and variables

Put `compose.yaml`, `.env.example`, `backup.sh`, `restore.sh`, and the `proxy`
directory into a directory of their own:

```bash
mkdir -p ~/services/home-assistant
cd ~/services/home-assistant
cp .env.example .env
chmod 600 .env
```

`.env` defines:

- `HOMEASSISTANT_VERSION` — the pinned image tag, identical to the release number;
- `HOMEASSISTANT_BIND` — the address the panel is published on, `127.0.0.1` by default;
- `HOMEASSISTANT_PORT` — the published port of the panel, `8123` by default;
- `HOMEASSISTANT_CONFIG_VOLUME` — the volume holding the `/config` directory;
- `TZ` — the time zone; time-based automations and charts depend on it.

All user data lives in a single volume: `configuration.yaml`,
`automations.yaml`, the `home-assistant_v2.db` history database, and the
`.storage` directory with accounts, tokens, and integration settings. No data
stays in the recipe directory.

### 3. Start the container on a VPS

<!-- coverage:deployment-vps -->

```bash
docker compose pull
docker compose up -d
docker compose ps
```

The first start takes longer than usual: the container unpacks `/config` and
brings the core up. Wait for the `healthy` state — the healthcheck requests
`/manifest.json` inside the container:

```bash
docker compose logs --tail=50 home-assistant
```

With the default settings no port faces the outside: the panel is bound to
`127.0.0.1`. On a VPS it should stay that way — grant access either through a
reverse proxy with HTTPS (step 6) or over a VPN, by setting
`HOMEASSISTANT_BIND` to the VPN interface address.

### 4. Complete the onboarding wizard

The panel is reachable locally only, so forward the port over SSH:

```bash
ssh -L 8123:127.0.0.1:8123 user@server.example
```

Open `http://localhost:8123`. The wizard creates the first account, which
becomes the owner of the server. Choose a long password and store it in a
password manager: resetting it is only possible by editing files in the volume.
Next the wizard asks for the home name, location, and units — sunset and sunrise
automations depend on the coordinates.

Enable two-factor authentication right after the wizard: the user avatar in the
bottom left corner → "Security" → "Multi-factor authentication".

### 5. Access from the local network

<!-- coverage:deployment-lan -->

The Home Assistant companion apps for Android and iOS need the server's direct
address on the local network. Set the server address in `.env` and recreate the
container:

```bash
sed -i 's/^HOMEASSISTANT_BIND=.*/HOMEASSISTANT_BIND=192.168.1.10/' .env
docker compose up -d
docker compose port home-assistant 8123
```

Never use `0.0.0.0`: on a VPS that exposes the control panel of your home to the
whole internet. Restrict the port to the local subnet:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 8123 proto tcp
```

Automatic device discovery does not work in this recipe: the container lives on
an isolated Compose network and never sees the mDNS, SSDP, and DHCP broadcasts.
Integrations are added by hand — "Settings" → "Devices & services" → "Add
integration", entering the device IP address. Bluetooth and USB Zigbee or Z-Wave
adapters require passing the device into the container and are not part of the
recipe.

### 6. Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Ready-made samples live in `proxy/Caddyfile`, `proxy/nginx.conf`, and
`proxy/traefik.yaml`; replace `home.example.com` with your own domain. Caddy
obtains the certificate automatically, the Nginx sample assumes a Certbot
certificate, and Traefik uses the `letsencrypt` resolver. The interface runs over
WebSocket: in the Nginx sample the `Upgrade` and `Connection` headers take care
of it, and without them the panel stays blank.

Home Assistant rejects proxied requests by default. Add an `http` block with
your proxy address to `configuration.yaml`:

```bash
docker compose exec home-assistant vi /config/configuration.yaml
```

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
```

Only the proxy's own address belongs in `trusted_proxies`. An extra subnet in
that list lets an attacker spoof the client address and bypass the brute-force
protection
([http documentation](https://www.home-assistant.io/integrations/http/#use_x_forwarded_for)).
If the proxy runs in a container, use its Docker network address instead of
`127.0.0.1`. Check the configuration and restart the server:

```bash
docker compose exec home-assistant python -m homeassistant --script check_config -c /config
docker compose restart home-assistant
```

The panel controls locks and cameras, so publish it only with two-factor
authentication enabled, and consider restricting access by IP on the proxy side.

### Backup

<!-- coverage:backup -->

The data lives in the `home-assistant-config` volume. The script stops the
container while archiving: history is written to SQLite, and a copy of a running
database comes out inconsistent.

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The archive appears in `./backups`. It contains access tokens, integration
passwords, and the history of your home, so keep the copy off the server and
encrypted.

The application has a built-in mechanism of its own: "Settings" → "System" →
"Backups". It stores archives in `/config/backups`, that is inside the same
volume, and protects against a bad configuration edit but not against losing the
server. The script and the built-in backups complement each other.

### Restore

<!-- coverage:restore -->

Restoring completely replaces the volume content with the chosen archive:

```bash
./restore.sh ./backups/home-assistant-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
```

Before unpacking, the script creates a safety copy of the current data. The image
version in `.env` must match the one the archive was created with: an older
version is not obliged to understand `.storage` files upgraded by a newer one.

### Update

<!-- coverage:update -->

Releases ship monthly and regularly contain breaking integration changes. Always
read the
[Backward-incompatible changes](https://www.home-assistant.io/blog/categories/release-notes/)
section of your release notes, then:

```bash
./backup.sh
sed -i 's/^HOMEASSISTANT_VERSION=.*/HOMEASSISTANT_VERSION=2026.9.0/' .env
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 home-assistant
```

Updating from the panel is unavailable in this install: without Supervisor the
image tag defines the version. The Home Assistant Core update button never
appears in the interface.

### Rollback

<!-- coverage:rollback -->

Restore the previous `HOMEASSISTANT_VERSION` value in `.env` and run
`docker compose pull` and `docker compose up -d`. This does not always work: on
update Home Assistant migrates the `.storage` files and the history database
schema to the new format, and there is no reverse migration. If the older version
refuses to start, restore the archive created before the update:

```bash
./restore.sh ./backups/home-assistant-YYYYMMDDTHHMMSSZ.tar.gz
docker compose up -d
```

The recipe has no separate external database, so every migration is limited to
the volume content.

### Complete removal

<!-- coverage:removal -->

Keep the data: `docker compose down`. Remove the container and all data
permanently:

```bash
docker compose down
docker volume rm home-assistant-config
rm -rf ~/services/home-assistant
```

Separately revoke access in the companion apps and remove the server from their
settings: they keep long-lived tokens of their own. If any devices were linked to
vendor clouds, unlink them on the vendor's side.

Sources: [Container install](https://www.home-assistant.io/installation/linux#docker-compose),
[http integration](https://www.home-assistant.io/integrations/http/),
[backups](https://www.home-assistant.io/common-tasks/general/#backups), and
[release notes](https://www.home-assistant.io/blog/categories/release-notes/).
