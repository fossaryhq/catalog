### PhotoPrism does not become healthy

```bash
docker compose ps
docker compose logs --tail=200 photoprism mariadb
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q photoprism)"
```

First startup and TensorFlow installation take time. Check free RAM, swap, and
disk, originals/storage permissions, and replacement of all three passwords.

### MariaDB connection fails

```bash
docker compose exec mariadb healthcheck.sh --connect --innodb_initialized
docker compose exec photoprism photoprism show config | grep -i database
```

The `.env` password takes effect when the volume is initialized. Changing it
does not alter an existing MariaDB user. Restore the old value or explicitly
change the database password. Never remove the volume without a verified dump.

### Indexing fails or the container restarts

Upstream warns that less than 4 GB swap and hard memory limits may cause
restarts while large files are processed. Check `free -h`, `docker stats`, logs,
and storage space. Do not start another complete index before a backup.

### The library is empty after startup

Verify that `PHOTOPRISM_ORIGINALS_PATH` points to media and is readable:

```bash
docker compose exec photoprism find /photoprism/originals -maxdepth 2 -type f | head
docker compose exec photoprism photoprism index
```

### The reverse proxy returns 502 or wrong links

On the host, check `curl http://127.0.0.1:2342/api/v1/status`.
`PHOTOPRISM_SITE_URL` must exactly match the public HTTPS URL and end in `/`.
A containerized proxy cannot reach host localhost without a host gateway.

### PhotoPrism fails after an update

Do not roll back only the image tag over a migrated database. Inspect migration
logs, restore the previous Compose and `.env`, then restore one consistent
pre-update archive containing the MariaDB dump, storage, and originals.
