## Container does not become healthy

Run `docker compose ps`, `docker compose logs --tail=100 memos`, and `docker compose config --quiet`. Check the exact image tag, free disk space, and whether `config/` was copied as a directory. Invalid deployment JSON stops startup. The native health endpoint is `/healthz` and answers `Service ready.`.

## Setup or registration looks unavailable

The first account is created at the initial setup page. After that, public registration is deliberately disabled; administrators add users in settings. File-backed GENERAL and ACCESS settings are read-only in the UI. Edit the matching JSON and restart only when you intend to change that policy.

## Wrong URLs or rate limits behind a proxy

Check `MEMOS_URL`, the proxy headers, and `MEMOS_TRUSTED_PROXIES`. The canonical URL does not make the instance public. Trust only real proxy addresses; never accept arbitrary client-supplied forwarded headers. Keep port 5230 on loopback.

## Notes or files are missing after recovery

Use the same version and the complete volume archive. A personal export or an SQLite file without its attachments is not a full backup. Check active `config/` and `.env`; archived configuration is not activated. Re-login and verify the attachment bytes. Administrators can inspect private notes; privacy does not imply encryption.

## Permission or SQLite errors

The official entrypoint normally sets the data owner to UID/GID 10001. Check `docker compose logs`, `df -h`, and the volume mount with `docker inspect`. Use local storage and one writer instance; do not put SQLite on an unreliable network filesystem or manually edit the live database. Preserve the original volume while investigating.

Sources: [docs](https://usememos.com/docs), [deployment configuration](https://github.com/usememos/memos/blob/v0.31.0/docs/configuration-provisioning.md).
