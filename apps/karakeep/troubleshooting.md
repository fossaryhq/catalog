## Startup or healthcheck failure

Run `docker compose ps --all` and `docker compose logs --tail=200 karakeep meilisearch chrome`. Check free disk and RAM with `df -h` and `free -m`. Browser jobs need more memory than an idle instance. Confirm you replaced both secrets and retained the Meilisearch key between restarts. `docker compose config --quiet` checks interpolation; avoid sharing the full rendered configuration because it contains secrets.

## Login fails or cookies disappear

Check that `KARAKEEP_URL` is the exact origin you opened, including scheme and nonstandard port. An HTTPS origin needs HTTPS and correct forwarded headers. For first setup use `http://localhost:3000` through the SSH tunnel. Registration is deliberately disabled; temporarily enable it only in a trusted setup window, then disable it and recreate the app. OIDC and SMTP require additional upstream configuration and are not included.

## A page will not archive

Check Chrome health and crawler logs. Paywalls, login pages, bot protection, large files, and unsupported sites may prevent capture. Private/internal targets are blocked by default; do not disable SSRF protections to fix an arbitrary bookmark. The app and browser need outbound access. Do not publish the Chrome debugging port as a workaround.

## Search stopped after an engine update

Read the Meilisearch logs for an incompatible database-version message. Restore the old engine together with the matching full backup, or follow the official index migration/rebuild guide. Do not remove the whole library volume to rebuild a disposable search index.

## Backup or restore failed

Use a trusted archive produced by this recipe, matching images, and the matching secrets from the archived configuration. The scripts require created containers to discover the exact named volumes. Review errors before restarting writers; a failed replacement must not be treated as successful recovery. Keep the source archive and the safety backup until login, private content, files, and search are verified.

Sources: [configuration](https://docs.karakeep.app/configuration), [security](https://docs.karakeep.app/administration/security-considerations), [Meilisearch upgrade](https://github.com/karakeep-app/karakeep/blob/v0.34.1/docs/docs/06-administration/10-meilisearch-upgrade.md).
