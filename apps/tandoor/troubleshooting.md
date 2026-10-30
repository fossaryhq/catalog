# Troubleshooting Tandoor

<!-- coverage:diagnostics -->
Start with `docker compose ps --all`, `docker compose logs --tail=200 tandoor database initialize`, `docker compose --env-file .env config --quiet`, and `curl -i http://127.0.0.1:8089/accounts/login/`. Keep secrets, session cookies and household data out of public reports.

- **The app restarts before HTTP starts:** replace both template secrets. `TANDOOR_SECRET_KEY` must be at least 50 characters. Preserve an existing key when recovering an established installation.
- **PostgreSQL rejects the password:** an initialized role keeps its password. Restore the original `.env` value or deliberately change the role password; deleting volumes destroys user data.
- **Permission denied in media/static:** inspect the initializer and volume mounts. The recipe runs as UID/GID 65534 and prepares the volume roots before startup. Restore matching ownership instead of making directories world-writable. Static assets are regenerated and do not need to be copied from an older image.
- **HTTP 400 or CSRF failure:** `TANDOOR_ALLOWED_HOSTS` takes hostnames/IPs without scheme or port; `TANDOOR_CSRF_TRUSTED_ORIGINS` takes complete origins. Include the actual hostname, scheme and any nonstandard port, forward Host/protocol correctly, then recreate the app. Keep the backend reachable only through trusted paths.
- **HTTP 500 at `/setup/` after creating the owner:** this is upstream [#4907](https://github.com/TandoorRecipes/recipes/issues/4907), still present in 2.7.2. Use `/account/login/`; do not delete the database or repeat owner creation. The normal headless login and recipe API work independently of that old redirect.
- **Forgotten owner password without SMTP:** use the upstream Django command `docker compose exec tandoor /opt/recipes/venv/bin/python manage.py changepassword <username>`. It prompts interactively; keep the new password out of command history. Configure SMTP before relying on email verification/reset.
- **Images are missing after recovery:** restore PostgreSQL and the complete media archive together, with the corresponding secret and version. Inspect app/Nginx logs and file ownership. Do not confuse regenerated static files with user media.
- **A private image opens without login:** media are served directly by Nginx. The recipe does not promise private image URLs; remove sensitive uploads rather than relying on the recipe's private flag for file authorization.
- **No AI import, external storage or identity provider:** these are intentionally unconfigured. They are not required for ordinary recipe storage, meal planning or shopping lists. Read the official integration instructions before enabling them.
- **An upgrade fails:** close access, keep the previous configuration and restore the pre-upgrade archive with its matching image. Do not force an older app over the newer schema or replace PostgreSQL with a different major version over its existing directory.

References: [Docker guide](https://docs.tandoor.dev/install/docker/), [configuration](https://docs.tandoor.dev/system/configuration/), [authentication](https://docs.tandoor.dev/features/authentication/) and [upstream issues](https://github.com/TandoorRecipes/recipes/issues).
