Home Assistant is a smart home server that collects devices from different
vendors into one panel and runs automations locally. Lights, sensors, air
conditioners, vacuums, TVs, and meters end up in a shared interface where they
can be controlled and wired to each other: "half an hour before sunset, turn on
the living room lights if somebody is home".

The key difference from Google Home, Alexa, or Yandex Smart Home is that the
logic lives on your own server. Devices keep working when the internet is down
or the vendor shuts its cloud service off, and the state history stays in a
local database. More than two thousand integrations cover both local protocols
(Zigbee, Z-Wave, MQTT, ESPHome, Matter) and cloud APIs.

The recipe runs the official Container install: one container and one Docker
volume holding the `/config` directory, with the panel on `127.0.0.1:8123`. This
install has no Supervisor, so add-ons, in-panel updates, and automatic discovery
of devices on the local network are unavailable — integrations are added by
device address, and updates happen by changing the image tag.

<!-- coverage:security-assessment -->

### Security assessment

The container runs without `privileged`, host networking, and the Docker socket,
with `no-new-privileges`, and the panel is published on `127.0.0.1` only by
default. That is a deliberate trade of convenience: the upstream instructions
suggest `network_mode: host` and `privileged: true` so that discovery,
Bluetooth, and USB adapters work. Such a container gets access to the host's
entire network and nearly all root capabilities, so the recipe leaves it out.

A Home Assistant account controls locks, cameras, and heating, which means the
physical security of the home. The panel may only be exposed over HTTPS and only
with two-factor authentication enabled in the user profile.

The reverse proxy deserves separate attention. Home Assistant rejects proxied
requests until
[`use_x_forwarded_for` and `trusted_proxies`](https://www.home-assistant.io/integrations/http/#use_x_forwarded_for)
are set in `configuration.yaml`. Listing too wide a subnet in `trusted_proxies`
lets an attacker spoof the client address and bypass the built-in brute-force
protection — only the proxy's own address belongs on that list.

The `/config` directory holds access tokens, integration passwords, and a
detailed history of life in the home. Backup archives must be encrypted and kept
off the server.
