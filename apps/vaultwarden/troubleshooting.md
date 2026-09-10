### Container does not become healthy

```bash
docker compose ps
docker compose logs --tail=200 vaultwarden
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q vaultwarden)"
```

Check free disk space and volume write access. The `/alive` endpoint verifies
both HTTP service and a database connection.

### Web vault reports an insecure context

The message is "Insecure URL not allowed. All URLs must use HTTPS." The web
vault checks the scheme of every address it calls and rejects plain HTTP from
anywhere, `localhost` included — the page loads, and the first request that
needs the server fails. Confirm that you opened an `https://` address, that
`VAULTWARDEN_DOMAIN` starts with `https://` and matches it, that the certificate
serves the full chain, and that the proxy forwards `Host` and
`X-Forwarded-Proto`. On a LAN with no public domain, issue a local certificate
(Caddy's `tls internal`, or `mkcert`) and trust its authority on the device.

### Clients do not synchronize immediately

WebSockets use the main port and `/notifications/hub`. Check the `Upgrade` and
`Connection` headers in Nginx. Caddy and Traefik handle protocol upgrades
automatically. Mobile push notifications require separate upstream setup and
are outside this recipe's test scope.

### A user cannot register

This is the secure default. Temporarily set
`VAULTWARDEN_SIGNUPS_ALLOWED=true`, run `docker compose up -d`, create the
required account over a protected connection, and immediately restore `false`.

### Changes in `.env` have no effect

If settings were previously saved through `/admin`, `/data/config.json`
overrides matching environment variables. Inspect diagnostics and the file, but
do not publish it: it may contain tokens and SMTP passwords.

### The installation looks empty after an update

Confirm that the original volume is attached and do not create a new user:

```bash
docker compose config
docker volume inspect vaultwarden-data
docker compose exec vaultwarden ls -la /data
```

If the wrong volume is selected, stop the container and correct
`VAULTWARDEN_DATA_VOLUME`. Do not remove the old volume before checking a backup.
