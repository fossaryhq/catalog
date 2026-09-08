### The container never turns healthy

Look at the status and the last messages:

```bash
docker compose ps
docker compose logs --tail=200 uptime-kuma
```

A first start takes a while: the container prepares the database before it
answers. If it stays unhealthy after that, check free disk space and that the
volume is writable — a read-only mount fails quietly here.

### The page loads, then stops updating

Uptime Kuma pushes state over a WebSocket. If the dashboard renders once and then
freezes, the reverse proxy is dropping the upgrade: check that it forwards the
`Upgrade` and `Connection` headers. Caddy does this on its own; Nginx and Traefik
need it configured, and the examples in `proxy/` already do.

### Port 3001 is taken

Change `UPTIME_KUMA_PORT` in `.env` — to `3101`, for instance — and recreate the
container:

```bash
docker compose up -d
```

If a reverse proxy on the host points at the old port, update its upstream too.

### An update left you with an empty instance

You are almost certainly on a different volume, not on lost data. Check which one
the container actually mounts:

```bash
docker volume inspect uptime-kuma-data
docker compose config
```

Do not create a new administrator and do not delete the old volume until you have
confirmed the data path and that a backup exists. Creating the administrator
again is what makes the empty instance permanent.
