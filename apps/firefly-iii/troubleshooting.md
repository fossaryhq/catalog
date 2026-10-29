# Troubleshooting Firefly III

<!-- coverage:diagnostics -->
Start with `docker compose ps --all`, `docker compose logs --tail=200 firefly database cron`, `docker compose --env-file .env config --quiet`, and `curl -i http://127.0.0.1:8088/health`. Do not paste resolved configuration, tokens, financial records or password-reset links into a public issue.

- **The application restarts immediately:** check the credential guard message. `FIREFLY_APP_KEY` and `FIREFLY_CRON_TOKEN` must be independent 32-character values; replace the template database password. Never rotate an established encryption key to fix a startup error.
- **Database authentication fails:** changing `.env` does not change the password in an initialized PostgreSQL volume. Restore the original secret or deliberately alter the database role password; do not delete volumes holding financial data.
- **The first visitor created the wrong owner:** close access immediately. For a genuinely empty, disposable installation, remove its volumes and bootstrap again over loopback. If records already exist, preserve a backup and follow upstream account recovery guidance instead of resetting data.
- **Registration is unavailable:** this is expected after the first account in default single-user mode. Use owner invitations or review the upstream multi-user settings deliberately; do not disable the protection merely to complete a smoke test.
- **HTTPS redirects, session or CSRF errors:** compare `FIREFLY_URL` with the real browser origin, forward the original host/protocol and trust only the proxy address. Recreate the service after env changes. Check that the proxy does not send requests to its own loopback address.
- **No recurring transactions or automatic budgets:** check the cron container and its crontab with `docker compose exec cron crontab -l`. Its schedule is 03:00 UTC regardless of `TZ`. To check manually, use `docker compose exec firefly php artisan firefly-iii:cron`; a daily job may report that it already ran. Treat the static HTTP token and access logs as secrets.
- **Attachments or API tokens fail after recovery:** restore the matching `FIREFLY_APP_KEY`, the PostgreSQL dump, storage keys and uploads together. Replacing only the database is incomplete. Protect a copy of the current volumes before attempting another restore.
- **Upgrade failure:** leave access closed, inspect the application migration log and restore a pre-upgrade archive with the matching image. Do not remove database tables or force an older image over the upgraded schema.
- **No bank feed or email:** neither the Data Importer nor SMTP is configured. Browser file exports are not backups. Review the official installation and mail documentation before enabling integrations.

References: [Docker FAQ](https://docs.firefly-iii.org/references/faq/docker/), [backup guide](https://docs.firefly-iii.org/how-to/firefly-iii/advanced/backup/), [cron](https://docs.firefly-iii.org/how-to/firefly-iii/advanced/cron/), and [upstream issues](https://github.com/firefly-iii/firefly-iii/issues).
