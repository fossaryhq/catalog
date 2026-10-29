## Initialization failed and the web app never started

Run `docker compose ps --all` and `docker compose logs --tail=200 initialize wallabag`. Replace both template secrets, use an administrator password of at least 16 characters, and keep the administrator named `wallabag`. Do not bypass the initializer: it removes the known upstream credentials before HTTP starts. After correcting `.env`, run `docker compose up -d --wait --wait-timeout 600`.

For a migration error, check disk with `df -h`, RAM with `free -m`, and the exact image version. Do not delete the database to fix startup. Keep a full backup before investigating.

## A password change did not survive restart

The initializer enforces `WALLABAG_ADMIN_PASSWORD` for the deployment-owned administrator. Change that value in `.env` and recreate the stack to rotate it. A UI-only password change is overwritten on initialization. Deleting or renaming that administrator prevents initialization; use the matching backup or official console tools to recover it.

## Login redirects to the wrong address

Check that `WALLABAG_URL` matches the browser origin and that the proxy forwards `Host` and `X-Forwarded-Proto`. Use `http://localhost:8087` through the SSH tunnel for initial setup. Do not post the full output of `docker compose config`: it includes secrets.

## An article is missing or unreadable

Paywalls, authentication, JavaScript-only pages, publisher changes, and unsupported layouts can prevent extraction. Confirm the source is reachable, review application logs, and try a public article. Restrict access to trusted users rather than opening the server's internal network to every submitted URL. Check disk usage if cached images stop appearing.

## A client or second factor does not work

Create an OAuth client in API/developer settings and use the documented OAuth2 flow; this is not OIDC single sign-on. Tokens and client secrets are sensitive. Mobile clients, TOTP, and SMTP are outside the verified scenario; an email-based second factor cannot deliver messages until SMTP works. Keep a verified recovery path before enabling it.

## Backup or restore failed

Wait for initialization to complete. Use created containers and a trusted archive from this recipe. Confirm matching image versions and active secrets before recovery; the archived `.env` is not activated automatically. A failed replacement must not be treated as successful restoration. Keep both the source and safety archives until login, private articles, tags, images, and API access are checked.

Sources: [documentation](https://doc.wallabag.org/), [Docker image](https://github.com/wallabag/docker), [console commands](https://github.com/wallabag/wallabag/blob/2.6.15/doc/content/admin/console_commands.md), [OAuth](https://github.com/wallabag/wallabag/blob/2.6.15/doc/content/developer/api/oauth.md).
