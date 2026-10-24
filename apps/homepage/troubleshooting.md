## Diagnostics

```bash
docker compose ps
docker compose logs --tail=100 homepage
docker compose config --quiet
curl -fsS http://127.0.0.1:3000/api/healthcheck
```

**Host validation failed:** allow the exact browser host, including its port, in `HOMEPAGE_ALLOWED_HOSTS`. Do not use a wildcard. Health using the internal 127.0.0.1:3000 host does not prove that the external host works.

**Login loops or missing cookies:** `HOMEPAGE_EXTERNAL_URL` must match the browser's scheme and address. HTTPS creates secure cookies that cannot work through HTTP. Recreate the container after changing `.env`.

**YAML error or missing links:** check indentation in settings/services/bookmarks/widgets. Bookmarks have an extra list around `href`; services use an object. Restart after changes. Invalid configuration can break the dashboard while health still succeeds.

**Permission denied:** UID/GID 1000 needs access to config and logs. The initializer recursively changes ownership; never point it at a system directory or another application's data. NFS/root-squash may need storage-side permissions.

**Broken widget:** its URL must be reachable from the container; localhost means Homepage itself. Verify least-privilege token permissions. The recipe connects no Docker socket or Kubernetes credentials and does not install linked applications.

**Repeated password attempts:** limit the credential callback at the proxy or use a VPN/IP restriction. Logs include `Failed password sign-in attempt`; do not publish configuration dumps containing secrets.

**Backup/restore:** use the complete recipe and its `.env`; `FOSSARY_ENV_FILE` selects another environment file. Archives contain secrets. Failed extraction leaves the service stopped: inspect logs, free space, permissions and the safety archive before retrying. Start the recipe once on a new machine before restore.
