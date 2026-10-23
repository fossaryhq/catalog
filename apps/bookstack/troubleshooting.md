## Inspect startup and database health

```bash
docker compose ps
docker compose logs --tail=150 database bookstack
curl --fail http://127.0.0.1:6875/status
```

First startup initializes MariaDB and runs migrations. `/status` should return HTTP 200 with `database`, `cache`, and `session` all true. For a database error, verify the two database passwords and the database healthcheck. Editing initialization passwords in `.env` does not rotate an existing MariaDB user's password. Never delete a populated volume to fix a credential error.

## Missing or invalid APP_KEY

Generate one key with `printf 'base64:'; openssl rand -base64 32` before first start. An initialized instance needs its original key. Restore it from the protected backup instead of generating a replacement, especially when MFA is enabled.

## Login, links, or assets use the wrong address

Match `BOOKSTACK_APP_URL` exactly to the browser address, including HTTPS and port. Follow the URL-change procedure in `installation.md`, including `bookstack:update-url`, for an existing installation. Clear browser cookies after changing origin. Forward `Host` and `X-Forwarded-Proto` from the trusted HTTPS proxy and keep direct untrusted access blocked.

## Cannot sign in

The public initial account must be replaced. The documented `bookstack:create-admin --initial` command is for initial setup, not a general password reset. Use the upstream recovery procedure or configured email recovery for an existing account. Diagnose mail errors before relying on password-reset email; this recipe does not configure SMTP.

## Uploads fail or disk fills

Check `docker system df` and free disk space on the Docker host. `/config` and the database volume both grow; documents and attachments need room in addition to image layers. Check the reverse proxy request limit and LinuxServer/PHP upload settings together. For permissions, confirm `PUID` and `PGID` match the intended file owner; do not make private files world-writable.

## Backup or restore fails

Check database logs, free disk, and archive permissions. Restore accepts only the four required members produced by `backup.sh`; use a complete trusted archive, not a standalone SQL or config file. Keep the original archive untouched and compare archived `configuration.env` with active `.env` without publishing secrets. If replacement has started and fails, keep BookStack stopped until recovery is complete. Do not downgrade MariaDB's physical data directory.

Sources: [BookStack troubleshooting](https://www.bookstackapp.com/docs/admin/debugging/), [backup/restore](https://www.bookstackapp.com/docs/admin/backup-restore/), [system CLI](https://www.bookstackapp.com/docs/admin/system-cli/), and [LinuxServer image](https://docs.linuxserver.io/images/docker-bookstack/).
