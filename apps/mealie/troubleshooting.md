## The page does not open

Check that the container is healthy and that the host port is free:

```bash
docker compose ps
docker compose logs --tail=100 mealie
curl --fail http://127.0.0.1:9925/api/app/about
```

The default port is bound to loopback. For a remote server, use the HTTPS reverse proxy or an SSH tunnel instead of opening the port publicly.

## Login does not work

The `.env` values `MEALIE_ADMIN_EMAIL` and `MEALIE_ADMIN_PASSWORD` seed the initial account only. Editing them after the database has been initialized does not change the account password. Reset it from Mealie's administration UI or follow the official recovery instructions.

## Images or changes disappear after an update

Confirm that the `mealie-data` volume is mounted at `/app/data` and that `.env` names the expected volume. Do not run `docker compose down --volumes`; that deletes the database and uploads.

## Imports fail

Recipe imports make outbound HTTP requests from the Mealie container. Check DNS and outbound HTTPS access. Imports can fail when a website blocks automated requests; the page can still be entered manually. Limit instance access because user-triggered URL imports cause Mealie's server to fetch external pages.

## An upgrade fails

Read the release notes before changing `MEALIE_VERSION`. Restore the pre-upgrade archive with the matching previous image tag, and inspect:

```bash
docker compose logs --tail=200 mealie
```
