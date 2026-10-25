## Requirements and preparation

Use 64-bit Ubuntu 22.04+ or Debian 12+ with Docker Engine and Compose v2.24+. Plan for 2 CPU cores, 4 GB RAM (8 GB recommended), and 10 GB disk plus larger models, user data, and backups. This recipe is CPU-only; no GPU devices or Docker socket are mounted.

```bash
mkdir -p ~/services/open-webui
cd ~/services/open-webui
# Copy the complete recipe, scripts, and proxy/ here.
cp .env.example .env
chmod 600 .env
# Run twice: one service secret, one independent initial admin password.
openssl rand -hex 32
openssl rand -hex 32
```

Replace the two placeholders before starting. Every `.env.example` parameter:

| Parameter | Meaning |
| --- | --- |
| `OPEN_WEBUI_VERSION` | Exact app tag, initially `v0.12.4`, including `v`. |
| `OLLAMA_VERSION` | Independent exact inference-server tag, initially `0.40.10`. |
| `OPEN_WEBUI_PORT` | Loopback host port, default `3080`. |
| `OPEN_WEBUI_URL` | Exact browser origin, initially `http://localhost:3080`; use the external HTTPS origin behind a proxy. Also used for the CORS allowlist. |
| `OPEN_WEBUI_SECRET` | Random service secret; preserve it through recovery. |
| `OPEN_WEBUI_ADMIN_EMAIL` | Initial administrator login, replace `admin@example.com` with your address. |
| `OPEN_WEBUI_ADMIN_PASSWORD` | Independent strong initial password; used only when the database has no users. |
| `OPEN_WEBUI_TRUSTED_PROXIES` | Uvicorn forwarded-header trust, initially `127.0.0.1`. For a proxy set its actual IP/CIDR; do not use `*`. This does not enable identity-header login. |
| `OPEN_WEBUI_DATA_VOLUME` | SQLite, uploads, vector/cache data, and settings. |
| `OLLAMA_DATA_VOLUME` | Local model weights and Ollama state. |
| `TZ` | IANA time zone, default `Etc/UTC`. |
| `OPEN_WEBUI_BACKUP_DIR` | Optional absolute backup path; defaults to `backups/` beside the recipe. |

The scripts source `.env` as trusted shell configuration. Keep it private. Changing bootstrap email/password variables does not rotate an existing account. Some UI settings persist in SQLite and can override initial environment defaults.

## Start and sign in

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait --wait-timeout 600
curl --fail http://127.0.0.1:3080/health/db
```

The `permissions` helper exits after assigning both volumes to UID/GID 1000; both servers then run without root. Open `OPEN_WEBUI_URL` and sign in with the configured administrator email/password. If remote, first use `ssh -L 3080:127.0.0.1:3080 user@server` and the matching local URL. Verify the admin account and closed registration before exposing a proxy. Choose a language and theme in personal settings. There is no shared default password.

## Download and test a model

A running Ollama server initially has no chat model. Download one deliberately; this needs internet and disk space:

```bash
docker compose exec ollama ollama pull qwen3:0.6b
docker compose exec ollama ollama list
```

Refresh the model list in Open WebUI, select `qwen3:0.6b`, and send a short message. The example is about a 522 MB download, with additional runtime RAM; it is small and can give poor answers. Use its Apache-2.0 terms and review another model's license before downloading it. The tag may change upstream; the backup preserves the downloaded weights. Larger contexts and models need more RAM and disk. Keep Ollama internal. `OFFLINE_MODE=true` avoids Open WebUI model/update downloads; the image includes its default embedding cache, and explicit Ollama model pulls remain possible. External providers, GPU, plugins, voice, and web search are not configured.

## VPS

<!-- coverage:deployment-vps -->

Set the external HTTPS `OPEN_WEBUI_URL`, configure the proxy, and allow only SSH/HTTP/HTTPS through the firewall. Keep port 3080 on loopback and leave Ollama without a host port. Use a strong administrator password and encrypted off-server backups. A low-cost CPU VPS may answer slowly; size it for the chosen model rather than the web page.

## Trusted local network

<!-- coverage:deployment-lan -->

Use the SSH tunnel for personal access, or an HTTPS proxy for the LAN. If you deliberately bind to a private IP, restrict it with a firewall and keep authentication enabled. Match `OPEN_WEBUI_URL` to the browser origin; a different origin can break websocket/CORS checks. Do not expose Ollama as an unauthenticated LAN API.

## Domain and HTTPS

<!-- coverage:deployment-domain-https -->

Use a sample from `proxy/`: Caddy obtains certificates; Nginx needs certificate paths; Traefik needs `websecure` and a `letsencrypt` resolver. Samples run on the host and forward to `127.0.0.1:3080`. A containerized proxy needs a shared network and the internal app port 8080.

Set `OPEN_WEBUI_URL=https://chat.example.com` and the proxy's real IP/CIDR in `OPEN_WEBUI_TRUSTED_PROXIES`, then recreate with `docker compose up -d --wait --wait-timeout 600`. The proxy must support websocket upgrades and long inference responses. The Nginx sample permits 100 MB requests. Forwarded-header trust is separate from trusted-identity login, which this recipe leaves disabled. Review persisted UI settings after changes.

## Backup

<!-- coverage:backup -->

```bash
./backup.sh
```

The script stops both writers and archives both complete volumes, `.env`, and Compose into `backups/open-webui-<timestamp>.tar` with mode 600. Each server's previous running/stopped state is preserved. Weight archives can be large and backup time can interrupt active chats. Encrypt and copy the archive off-server: it holds private chats, files, models, initial credentials, and service secrets. Copying a live SQLite file or only exporting a chat is not a full backup.

## Restore

<!-- coverage:restore -->

**Restore replaces both volumes.** Use trusted archives, matching application/Ollama versions, and the original `OPEN_WEBUI_SECRET`. Compare archived `configuration.env` with active `.env` before restoring; it is not activated automatically.

```bash
# On a fresh host initialize the matching recipe first.
docker compose up -d --wait --wait-timeout 600
./restore.sh ./backups/open-webui-TIMESTAMP.tar
curl --fail http://127.0.0.1:3080/health/db
```

The payload is validated before replacement and a safety backup is created. A file-replacement failure leaves both servers stopped. After recovery, sign in, reopen a saved chat, download a file, and generate a new answer with a restored model. Recheck registration, providers, and sharing settings. The amd64 smoke removes both original volumes and verifies these operations, including the model digest and exact file bytes.

## Update

<!-- coverage:update -->

Read upstream release notes and model compatibility notes. Back up, keep an off-server copy, and change the reviewed exact tag in `.env`:

```bash
docker compose pull
docker compose up -d --wait --wait-timeout 600
docker compose logs --tail=100 open-webui ollama
```

App migrations run at startup. Ollama has an independent version: review its release notes before changing it. Do not change the service secret casually. Do not use `latest`, assume 0.x API compatibility, or remove branding outside the license's exceptions.

## Rollback

<!-- coverage:rollback -->

Never start an older app on a database migrated by a newer release. Stop both servers, set their old exact tags and original secret in `.env`, and recreate without starting:

```bash
docker compose stop open-webui ollama
# Edit both reviewed versions and preserve OPEN_WEBUI_SECRET.
docker compose pull open-webui ollama
docker compose create open-webui ollama
./restore.sh ./backups/open-webui-BEFORE-UPDATE.tar
```

The safety backup reads stopped volumes without launching the old app against new data. Restore the complete matching archive and verify a chat, file, and local inference. Keep the failed installation's backup until recovery is confirmed.

## Stop and remove

<!-- coverage:removal -->

`docker compose down` keeps both volumes. After verifying an off-server backup, `docker compose down --volumes` permanently deletes accounts, chats, files, model weights, and Ollama state. Removing the recipe directory also removes local backups and `.env`.

Sources: [documentation](https://docs.openwebui.com/), [environment configuration](https://docs.openwebui.com/getting-started/env-configuration/), [v0.12.4](https://github.com/open-webui/open-webui/releases/tag/v0.12.4), [Ollama](https://github.com/ollama/ollama), [Qwen model](https://ollama.com/library/qwen3:0.6b), [license](https://docs.openwebui.com/license/).
