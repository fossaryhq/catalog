### The container never becomes healthy

```bash
docker compose ps
docker compose logs --tail=200 miniflux database
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q miniflux)"
```

Miniflux exits on a bad configuration value rather than starting with a partial
one, and the message names the key. Two values fail most often: a database
password containing `@`, `/`, or `#`, which breaks `DATABASE_URL`, and an empty
`MINIFLUX_TRUSTED_PROXY_NETWORKS`, which is rejected with "at least one CIDR
notation network is required". The health check itself calls `/healthcheck`,
which pings the database, so a healthy container also means migrations ran.

### The administrator account was not created

`CREATE_ADMIN` only acts while the user table is empty. If the first start
failed after the schema was created, the account may be missing. Create it by
hand instead of wiping the volume:

```bash
docker compose exec miniflux miniflux -create-admin
```

### Wrong links, redirects, or a broken login after a proxy change

`MINIFLUX_BASE_URL` must match the public address exactly: scheme, host,
optional port and path, no trailing `/`. Miniflux builds cookie scope, OAuth2
redirects, and the Google Reader endpoint from it. Change the variable and
recreate the container; the value is read at startup.

### A mobile client cannot sign in

Use the Google Reader endpoint at `MINIFLUX_BASE_URL/googlereader` (or the Fever
endpoint at `/fever/`) and the separate API password from Settings → API keys,
not the web password. Nginx must pass `Authorization` through — the sample in
`proxy/nginx.conf` sets `proxy_pass_header Authorization` for that reason; Caddy
and Traefik forward it by default.

### Feeds stop updating or a feed is disabled

A feed is disabled after `MINIFLUX_POLLING_PARSING_ERROR_LIMIT` consecutive
failures; the feed page shows the last error. Check the feed by hand before
raising the limit:

```bash
docker compose exec miniflux miniflux -refresh-feeds
docker compose logs --tail=200 miniflux | grep -i "unable to"
```

A whole instance that stops polling usually means the poller cannot reach the
internet from the container, or `MINIFLUX_POLLING_FREQUENCY` is far higher than
expected.

### The client IP in the logs is the Docker gateway

That is what the recipe intends: `MINIFLUX_TRUSTED_PROXY_NETWORKS` trusts
loopback only, so forwarded headers are ignored and every request appears to
come from the bridge. If you need real client addresses, add only the bridge
network of this project to the variable and make sure the proxy sets
`X-Forwarded-For` itself. Trusting a broad range lets a caller spoof both the
client IP and, if `AUTH_PROXY_HEADER` is ever enabled, the authenticated user.

### The reverse proxy returns 502

On the host, run `curl -I http://127.0.0.1:8080/`. If that answers, the proxy is
looking at the wrong upstream: inside a proxy container `127.0.0.1` is the proxy
itself, not the host, so use a host gateway address or put the proxy on the same
Docker network. If it does not answer, the container is unhealthy — start from
the first section.

### The database volume keeps growing

Retained entries and downloaded icons dominate the size. Lower
`MINIFLUX_CLEANUP_ARCHIVE_READ_DAYS`, then reclaim space during a maintenance
window:

```bash
docker compose exec miniflux miniflux -flush-sessions
docker compose exec database vacuumdb --analyze --dbname=miniflux --username=miniflux
```
