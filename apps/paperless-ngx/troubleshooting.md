### Paperless-ngx does not become healthy

```bash
docker compose ps
docker compose logs --tail=200 webserver database broker
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q webserver)"
```

Verify that both required secrets were replaced, PostgreSQL and Valkey are
healthy, disk space is available, and `curl http://127.0.0.1:8000/` returns a
redirect. The first start takes longer while migrations, indexing, and OCR
language installation run.

### CSRF errors, wrong links, or redirects to another address

`PAPERLESS_URL` must exactly match the public origin: `https` scheme, domain,
optional nonstandard port, no trailing `/`, and no path. After changing it, run
`docker compose up -d --force-recreate webserver`. Verify that the proxy keeps
the original `Host` and sends `X-Forwarded-Proto`.

### Processing status does not update

Inspect the WebSocket route and broker:

```bash
docker compose logs --tail=200 webserver broker
docker compose exec broker valkey-cli ping
```

The proxy must permit connection upgrades for `/ws/status/`. A containerized
proxy cannot reach host `127.0.0.1` without a host gateway.

### OCR does not recognize a language

Two variables have to agree. `PAPERLESS_OCR_LANGUAGES` installs the tesseract
pack at container start, and `PAPERLESS_OCR_LANGUAGE` selects what to recognize;
naming a language only in the second one silently does nothing. For Russian
alongside English set `PAPERLESS_OCR_LANGUAGES=rus` and
`PAPERLESS_OCR_LANGUAGE=rus+eng`, then check the startup logs for the language
data installation. Re-run OCR on existing
documents through the UI only after a backup: it is CPU intensive and may
replace the archived rendition.

### A document remains in consume or processing fails

```bash
docker compose logs --since=30m webserver
docker system df
docker compose exec webserver document_sanity_checker
```

Check the format, volume permissions, free disk, and RAM. Tika and Gotenberg are
not included, so this stack cannot process Office and email files that require
them.

### An archive serial number is rejected as already taken

```
Document with this Archive Serial Number already exists in the trash.
```

Deleting a document moves it to the trash and it keeps its archive serial number
there for the retention period, so the number stays taken while the document is
nowhere in the list. Open **Trash** in the sidebar and delete that document
permanently, then assign the number again. The same applies to a document that
is consumed a second time after the first copy was deleted.

### The reverse proxy returns 502

On the host, run `curl -I http://127.0.0.1:8000/`. Then inspect the upstream,
firewall, and proxy network namespace. Inside a container, `127.0.0.1` refers to
that container, not Paperless-ngx on the host.
