### Forgejo does not become healthy

```bash
docker compose ps
docker compose logs --tail=200 forgejo database
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q forgejo)"
```

Check the database password, free disk space, and volume access. `/api/healthz`
must return JSON with `status: pass`.

### Permission denied under `/var/lib/gitea`

The rootless container runs as UID/GID 1000. Do not change `user` without
migrating ownership. Run `chown -R 1000:1000` before using a bind mount.

### Clone URLs show the wrong domain or port

Check `FORGEJO_ROOT_URL`, `FORGEJO_DOMAIN`, `FORGEJO_SSH_DOMAIN`, and
`FORGEJO_SSH_PORT`, then run `docker compose up -d --force-recreate`.

### SSH is not reachable externally

This is the safe default: SSH binds to localhost. Test through a tunnel first.
For public access, follow the VPS section, change only the SSH binding, inspect
the firewall, and diagnose with `ssh -vvv -p 2222 git@git.example.com`.

### The reverse proxy returns 502

Check `curl http://127.0.0.1:3000/api/healthz`, the upstream address, and whether
the proxy can reach host localhost. A containerized proxy has a different
localhost namespace.
