## Diagnostics
```bash
docker compose ps
docker compose logs --tail=100 beszel
docker compose exec beszel /beszel health --url http://127.0.0.1:8090
```

**Wrong password:** bootstrap environment applies only to a new database. Restore brings back old credentials. Use your authorized PocketBase password-reset procedure; never delete the volume just to reset login.

**No systems/metrics:** the recipe installs only the hub. Deploy a separate agent, assign the system to the user, and check its address, port, key and version. Localhost inside the hub means the hub container. Restrict SSH to the hub; WebSocket needs a correct HUB_URL, registration token, TLS and proxy upgrade.

**Permission denied:** the initializer makes the data volume owned by UID/GID1000. Never use another application's volume. Container root is read-only; data and temporary tmpfs are writable.

**Missing notifications:** SMTP/push is not configured. A saved alert rule does not prove delivery. Check the integration using the official documentation.

**Empty history:** newly connected systems collect measurements over time; aggregates arrive later. A user sees only assigned systems. Sandbox container measurements do not prove complete physical-host monitoring.

**Backup/restore:** FOSSARY_ENV_FILE selects another .env. Incomplete archives are rejected before stopping. Failed extraction leaves the hub stopped: inspect space, permissions, archive and safety copy. Archives contain credentials and a private SSH key; never publish them.
