### Linkwarden does not become healthy

```bash
docker compose ps
docker compose logs --tail=200 linkwarden postgres meilisearch
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q linkwarden)"
curl -I http://127.0.0.1:3000/
```

Check the three required distinct secrets, dependency health, free RAM, and disk
space. `POSTGRES_PASSWORD` must be URL-safe because it appears in `DATABASE_URL`.
Never delete production volumes while diagnosing a failure.

### Redirects or sign-in use the wrong URL

`LINKWARDEN_URL` must exactly match the public scheme and host without a trailing
`/`. The recipe passes `NEXTAUTH_URL=${LINKWARDEN_URL}/api/v1/auth` and
`BASE_URL=${LINKWARDEN_URL}`. Recreate Linkwarden after changing it and remove old
cookies. Ensure the proxy forwards the original `Host` and
`X-Forwarded-Proto=https`.

### Registration is still available

Set `NEXT_PUBLIC_DISABLE_REGISTRATION=true`, run
`docker compose up -d --force-recreate linkwarden`, and check in a private
window. A simple restart is insufficient when the container was not recreated.

### Preserved pages fail or use the application origin

Check `LINKWARDEN_USER_CONTENT_URL`, DNS, TLS, and the second proxy host. The
origin must differ from the application and must not share its cookies. Never
work around this by enabling private-network access or insecure TLS.

### An internal or self-signed URL cannot be preserved

This is expected protection: Compose pins `ALLOW_PRIVATE_NETWORK_ACCESS=false`
and `ALLOW_INSECURE_TLS=false`. Do not weaken them on a shared instance. For a
trusted internal resource, prefer a public endpoint with valid HTTPS or a
separate isolated instance with an egress firewall.

### Search does not return new bookmarks

```bash
docker compose logs --tail=200 meilisearch linkwarden
docker compose exec meilisearch curl --fail http://127.0.0.1:7700/health
```

Ensure both services have the same `MEILI_MASTER_KEY` and the volume is not full.
Do not delete the index before a complete backup. If upstream provides a reindex
command for this version, run it only after preserving PostgreSQL and archives.

### The reverse proxy returns 502

On the host, run `curl -I http://127.0.0.1:3000/`. Inspect the upstream, firewall,
and proxy namespace. Inside a container, `127.0.0.1` refers to the proxy itself,
not Linkwarden on the host; use a host gateway or shared private network.
