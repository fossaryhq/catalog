## 1. Check the server

Use Ubuntu 22.04+ or Debian 12+ with Docker Engine and Docker Compose v2.24+.
Node-RED needs 1 CPU, 256 MB RAM, and 2 GB of disk at minimum; reserve 512 MB
when flows use many nodes or keep sizeable context. This recipe has no separate
database: flows, installed nodes, and credentials live in a Docker volume.

```bash
docker --version
docker compose version
```

## 2. Prepare the recipe

Place all recipe files in a private directory, including `config/settings.js`:

```bash
mkdir -p ~/services/node-red
cd ~/services/node-red
cp .env.example .env
chmod 600 .env
```

Generate a bcrypt editor-password hash and a credential-encryption secret. Put
the hash, not the plain password, in `.env`; save the plain password and the
secret in a password manager. Never change `NODE_RED_CREDENTIAL_SECRET` after
creating credentials, or existing ones will no longer decrypt.

```bash
docker run --rm -it nodered/node-red:5.0.7-24 node-red admin hash-pw
openssl rand -hex 32
```

Set the first output as `NODE_RED_ADMIN_PASSWORD_HASH`, choose a non-default
`NODE_RED_ADMIN_USERNAME`, and set the second as `NODE_RED_CREDENTIAL_SECRET`.
`NODE_RED_SETTINGS_FILE` is the supplied JavaScript settings file; it enables
password login and must remain readable to the container.

## 3. Start Node-RED

<!-- coverage:deployment-vps -->

```bash
docker compose pull
docker compose up -d
docker compose ps
curl -I http://127.0.0.1:1880/
```

The last command returns an HTTP response, but the editor must ask for the
credentials configured above. First sign in through an SSH tunnel:

```bash
ssh -L 1880:127.0.0.1:1880 user@server.example
```

Open `http://localhost:1880`, sign in, drag an **Inject** node and a **Debug**
node onto a new flow, connect them, then click **Deploy**. This confirms that
the editor can save and run a flow. Do not put real tokens in an unencrypted
export or screenshot.

## Local network

<!-- coverage:deployment-lan -->

Keep the localhost bind and use the SSH tunnel where possible. To expose it to
a trusted LAN, replace `127.0.0.1` in the port mapping with the server's LAN IP
(for example `192.168.1.10`) and firewall port 1880 from every other network.
Never bind the unauthenticated port to all interfaces; password login is not a
replacement for TLS or network access control.

## Domain and HTTPS

<!-- coverage:deployment-domain-https -->

The `proxy/` directory contains Caddy, Nginx, and Traefik examples for
`flows.example.com`. Replace it with your name. Caddy requests TLS
automatically; Nginx expects existing Certbot certificates; Traefik uses a
resolver called `letsencrypt`. Forward `Host`, `X-Forwarded-For`, and
`X-Forwarded-Proto` unchanged if adapting an example. Sign in through the HTTPS
address before publishing any webhook endpoint.

## Backup

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

The script stops Node-RED briefly and archives its complete data volume. That
includes flows, installed palette modules, and encrypted credentials. Copy the
archive off the server encrypted; keep the `.env` credential secret and the
recipe's `config/settings.js` with it, but separately protected.

## Restore

<!-- coverage:restore -->

Restore irreversibly replaces the current data volume. The script creates a
safety backup first, then restores the selected archive:

```bash
./restore.sh ./backups/node-red-YYYYMMDDTHHMMSSZ.tar.gz
docker compose up -d
```

Open the editor and deploy a harmless saved flow. Use the same
`NODE_RED_CREDENTIAL_SECRET` from the time of the backup; without it, encrypted
credentials cannot be used.

## Update

<!-- coverage:update -->

Back up first, read the [release notes](https://github.com/node-red/node-red/releases),
change `NODE_RED_VERSION` in `.env`, and recreate the service:

```bash
docker compose pull
docker compose up -d
docker compose logs --tail=100 node-red
```

Sign in and deploy a small existing flow. Review release notes before changing
the Node.js variant (`-24`) or installed third-party nodes.

## Rollback

<!-- coverage:rollback -->

Put the old image tag back in `.env` and recreate the container. If it cannot
read data changed by the new release, restore the backup created before update:

```bash
docker compose up -d
./restore.sh ./backups/node-red-PRE-UPDATE.tar.gz
```

## Complete removal

<!-- coverage:removal -->

`docker compose down` stops the service but preserves flows. To remove all
application data after verifying an off-server backup:

```bash
docker compose down
docker volume rm node-red-data
rm -rf ~/services/node-red
```

Sources: [official Docker guide](https://nodered.org/docs/getting-started/docker),
[securing the editor](https://nodered.org/docs/user-guide/runtime/securing-node-red),
and [projects and flow files](https://nodered.org/docs/user-guide/projects/).
