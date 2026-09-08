### "Access through untrusted domain"

Nextcloud only accepts requests from domains on its list. Add yours to `.env` and
restart:

```bash
grep NEXTCLOUD_TRUSTED_DOMAINS .env
docker compose up -d
docker compose exec -u www-data app php occ config:system:get trusted_domains
```

The variable is applied at container start; to change the list on a running
instance use
`occ config:system:set trusted_domains 1 --value=cloud.example.com`.

### Links point to http instead of https

Behind a reverse proxy Nextcloud does not know the outside is HTTPS. Fill in
`NEXTCLOUD_TRUSTED_PROXIES`, `NEXTCLOUD_OVERWRITE_PROTOCOL=https`, and
`NEXTCLOUD_OVERWRITE_CLI_URL` in `.env`, then restart the stack.

### Calendar and contacts do not connect in clients

Clients look for `/.well-known/caldav` and `/.well-known/carddav`. Those
addresses have to redirect to `/remote.php/dav` — the samples in `proxy/` already
carry the rules. Check with:

```bash
curl -sI https://cloud.example.com/.well-known/caldav | head -3
```

### Background jobs do not run

```bash
docker compose ps cron
docker compose exec -u www-data app php occ config:app:get core backgroundjobs_mode
docker compose logs --tail=50 cron
```

The mode must be `cron`. The value is written the first time `cron.php` runs, so
right after installation the field can be empty — the `cron` container executes
the job every five minutes.

### Large files fail to upload

The limit usually comes from the reverse proxy rather than PHP. Nginx needs
`client_max_body_size`, Caddy needs `request_body max_size`, and Traefik needs
the `buffering` middleware; the samples in `proxy/` are already configured. On
the PHP side the size comes from `NEXTCLOUD_PHP_UPLOAD_LIMIT`.

### Permission error on the data directory

Inside the container Nextcloud runs as UID 33:

```bash
ls -ld /srv/nextcloud/data
sudo chown -R 33:33 /srv/nextcloud/data
```

### Files appeared on disk but not in the interface

Nextcloud keeps the file list in the database and does not scan the directory on
its own. After copying files by hand, run:

```bash
docker compose exec -u www-data app php occ files:scan --all
```

### The instance is stuck in maintenance mode

That happens when an upgrade was interrupted:

```bash
docker compose exec -u www-data app php occ maintenance:mode --off
docker compose exec -u www-data app php occ status
```

If the server complains about an unfinished upgrade, run `occ upgrade` first, and
restore from an archive if that fails.

### The checks page shows warnings

That is a normal state right after installation: some checks concern HTTPS and
headers that only appear once the instance is published through a reverse proxy.
Walk the list under Administration → Overview and close the items one by one —
each links to the relevant documentation.

### The server does not start after an update

```bash
docker compose logs --tail=200 app | grep -i "error\|upgrade\|migration"
```

You cannot skip a major version: upgrade one at a time. Downgrades are not
supported — the only way back is restoring the archive taken before the update.
