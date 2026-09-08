### The container never becomes healthy

```bash
docker compose ps
docker compose logs --tail=200 jellyfin
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q jellyfin)"
```

The image healthcheck calls `http://localhost:8096/health` inside the container.
The usual causes are permissions on the `/config` volume or a full disk.

### The library is empty after a scan

Check the path: the library must point at the path inside the container
(`/media/Movies`), not the host path (`/srv/media/Movies`).

```bash
docker compose exec jellyfin ls -la /media
```

If the directory is visible but nothing is found, it is the naming. Jellyfin
expects one directory per movie with the year in parentheses; files like
`film1.mkv` dumped in one folder are not recognized.

### Artwork and descriptions were not fetched

Metadata comes from external providers, so the server needs internet access.
Check connectivity and refresh manually:

```bash
docker compose exec jellyfin curl -sI https://api.themoviedb.org | head -1
```

Then use Dashboard → Libraries → Scan All Libraries. For a single movie, the
"Identify" action with a manual year or database link usually fixes it.

### Video does not play or stutters

Open Dashboard → Playback and check whether transcoding is running. Direct play
barely loads the server; a 4K transcode saturates the CPU. Hardware acceleration
is not configured in this recipe; to enable it, pass the device through in
`compose.yaml`:

```yaml
    devices:
      - /dev/dri:/dev/dri
```

and pick the method under Dashboard → Playback → Transcoding. Make sure the user
inside the container can access the device.

### Seeking breaks behind a reverse proxy

Disable response buffering and allow WebSocket upgrades. Nginx needs
`proxy_buffering off` and the `Upgrade`/`Connection` headers; Caddy and Traefik
upgrade automatically. All samples in `proxy/` are already configured.

### The activity log shows one and the same IP address

That is the reverse proxy address. Add it under Dashboard → Networking → Known
proxies and the server will start trusting the `X-Forwarded-For` header.

### Clients do not find the server automatically

Autodiscovery uses UDP port 7359, which this recipe does not publish. Add
`- "7359:7359/udp"` to `ports`, or enter the server address in the client by
hand. DLNA requires host networking and is deliberately disabled here.

### The disk is filling up

```bash
docker system df -v | grep jellyfin
docker compose exec jellyfin du -sh /cache/* /config/metadata
```

The thumbnail and transcode cache can be deleted entirely; it will be rebuilt.
Metadata under `/config/metadata` grows with the library — deleting it means
downloading all the artwork again.

### The server does not start after an update

Look at the migration logs:

```bash
docker compose logs --tail=200 jellyfin | grep -i "migration\|error"
```

Jellyfin does not support downgrades: the only way back is restoring the archive
taken before the update.
