### The library is empty after startup

Check that the directory is visible inside the container and that the scan
finished:

```bash
docker compose exec navidrome ls -la /music
docker compose logs --tail=100 navidrome | grep -i scanner
```

An empty result with a visible directory almost always means missing tags:
Navidrome builds the library from `Artist`, `Album`, and `Title`, not from file
names. Inspect the tags of a single file with the built-in command:

```bash
docker compose exec navidrome /app/navidrome inspect "/music/path/to/file.mp3"
```

### New files do not show up

By default the recipe scans once a day (`NAVIDROME_SCAN_INTERVAL`). Trigger a
scan immediately from the web interface with the refresh button, or run:

```bash
docker compose exec navidrome /app/navidrome scan --datafolder /data
```

### No artwork

Artwork comes from the tag or from a `cover.jpg`, `folder.jpg`, or `front.jpg`
file next to the tracks. Make sure the file sits in the album directory and is
readable. The artwork cache lives in the `/data` volume and rebuilds itself.

### One album is split into several

This happens with compilations that have no `Album Artist` tag. Set the same
`Album Artist` on every track of the album (for example `Various Artists`) and
run a rescan.

### A Subsonic client cannot connect

The client needs the server address without `/app`, a username, and a password.
Check that the API answers:

```bash
curl --fail "https://music.example.com/rest/ping?v=1.16.1&c=check&f=json"
```

An authentication error means the API works. No answer at all points at the
reverse proxy or at `NAVIDROME_BASE_URL`.

### The web interface loads without styles

That happens when Navidrome is published under a subpath and `NAVIDROME_BASE_URL`
is not set. Use the same path as in the reverse proxy and restart the container.

### Seeking inside a track stutters

The reverse proxy is buffering the response. Nginx needs `proxy_buffering off`,
which the sample in `proxy/` already has. Caddy and Traefik stream without
buffering.

### The administrator password was lost

Change it with a command inside the container:

```bash
docker compose exec navidrome /app/navidrome user edit --datafolder /data
```

The command is interactive, so run it from a terminal with a TTY.

### The server does not start after an update

```bash
docker compose logs --tail=200 navidrome | grep -i "migration\|error"
```

Downgrades are not supported: the only way back is restoring the archive taken
before the update.
