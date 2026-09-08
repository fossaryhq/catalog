### One of the containers never becomes healthy

```bash
docker compose ps
docker compose logs --tail=200 immich-server
docker compose logs --tail=100 database
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q immich-server)"
```

`immich-server` will not start until the database passes its healthcheck. If the
database dies right after startup, the usual cause is volume permissions or a
changed `IMMICH_DB_PASSWORD` against an existing database: the password is set at
initialization and is not changed by the variable afterwards.

### The machine learning container restarts or crashes

On amd64, since v3 the image needs the x86-64-v2 microarchitecture level:

```bash
/usr/bin/ld.so --help | grep -m1 x86-64-v2
docker compose logs --tail=100 immich-machine-learning
```

If it is unsupported, turn machine learning off under Administration → Settings →
Machine Learning and remove the service from `compose.yaml`. Smart search, face
recognition, duplicate detection, and OCR will not work in that case.

### Uploads from the phone break on large videos

The limit comes from the reverse proxy, not from Immich. Nginx needs
`client_max_body_size 0` and raised `proxy_read_timeout` and
`proxy_send_timeout`, Caddy needs `request_body max_size`, and Traefik needs the
`buffering` middleware with `maxRequestBodyBytes: 0`. All three samples in
`proxy/` already carry these settings.

### The disk fills up although there are few photos

Besides originals, Immich stores thumbnails and transcoded videos. Check what
takes the space:

```bash
sudo du -sh /srv/immich/library/*
docker system df -v | grep immich
```

The `backups` directory holds automatic database dumps; their retention is set
under Administration → Settings → Backup. The model cache in the
`immich-model-cache` volume can be deleted — it will be downloaded again.

### Smart search returns nothing

Check that the jobs ran: Administration → Job Queues → Smart Search. The default
CLIP model understands English queries only. Searching in another language
requires a multilingual model, selected under Administration → Settings →
Machine Learning → Smart Search; after changing the model, re-run the Smart
Search job for the whole library.

### The server does not start after an update

Look at the migration logs:

```bash
docker compose logs --tail=200 immich-server | grep -i migration
```

Do not start the previous image against a migrated database — the only rollback
is restoring the archive taken before the update. Skipped major versions also
cause migration errors: upgrade one version at a time.

### Empty cards in the timeline after a restore

The database and the files came from different snapshots. Restore a consistent
pair from an archive created by `backup.sh`, and never mix `database.sql.gz` from
one archive with `library.tar.gz` from another.

### `restore.sh` fails with a psql error

A dump must not be loaded into a database the server has already used. The script
removes the database volume before restoring; if you restore by hand, make sure
the database is empty and that `immich-server` has never started against it.
