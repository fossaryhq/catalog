## Startup and database health

```bash
docker compose ps --all
docker compose logs --tail=150 vikunja database permissions
curl --fail http://127.0.0.1:3456/health
```

`permissions` should exit with code 0; it is a one-time ownership step, not a web service. PostgreSQL and Vikunja should become healthy. The app's built-in healthcheck avoids needing a shell or curl in its minimal image. Startup runs database migrations; wait for healthy status before creating accounts or using the API.

## Database authentication or locked SQLite database

This recipe uses PostgreSQL. If logs name SQLite or `database is locked`, check that you are running this Compose file and that `VIKUNJA_DATABASE_TYPE=postgres` reaches the container. Verify `VIKUNJA_DB_PASSWORD` matches the initialized PostgreSQL role. Editing initialization variables does not rotate existing credentials; never delete the database volume to fix a password mismatch.

## Cannot register or sign in

Public registration is intentionally disabled. Create an account through `vikunja user create` inside the container; no default password exists. Run `docker compose exec vikunja /app/vikunja/vikunja user --help` for supported recovery commands. SMTP must be configured before relying on email password recovery or task reminders. A `Pro features have been disabled` log line is expected for the free core and does not prevent lists or kanban.

## Wrong public address or desktop connection

Match `VIKUNJA_PUBLIC_URL` to the exact reachable browser URL, with scheme, port, and trailing slash, then recreate the app. Desktop clients need that server URL too. Keep `Host` and `X-Forwarded-Proto` correct at the HTTPS proxy. Changing the service secret invalidates issued tokens, so preserve it instead of generating a new one during a routine restart or restore.

## Upload or permission failures

Check free disk space on the Docker host and both volumes. The app writes to `/data` as `1000:1000`; inspect the `permissions` container instead of making files world-writable or running the app as root. The root filesystem is read-only by design. Requests must fit both the proxy limit and Vikunja's file-size limit (20 MB by default).

## Backup or restore fails

Use the complete archive from `backup.sh`, not a standalone dump or app-volume archive. Check disk space, PostgreSQL logs, and archive permissions. Restore replaces the database public schema and app files; after a failed replacement, leave Vikunja stopped until recovery is complete. Compare archived configuration with active `.env` without exposing credentials, and use matching versions. Do not downgrade a PostgreSQL physical data directory.

Sources: [CLI](https://vikunja.io/docs/cli/), [configuration](https://vikunja.io/docs/config-options/), [backup/restore](https://vikunja.io/docs/backup-restore/), and [official image](https://hub.docker.com/r/vikunja/vikunja).
