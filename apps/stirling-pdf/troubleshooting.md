### Stirling PDF does not become healthy

```bash
docker compose ps
docker compose logs --tail=200 stirling-pdf
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q stirling-pdf)"
curl -v http://127.0.0.1:8080/api/v1/info/status
```

The endpoint must return JSON with `status: UP`. First startup is slower while
H2 and tools are prepared. Verify 2 GB RAM, free disk space, port 8080, and
permissions on all four data directories.

### Initial credentials are rejected

`SECURITY_INITIALLOGIN_*` applies only while the first database is created. If
`configs` already contains `stirling-pdf-DB-*.mv.db`, editing `.env` does not
change that user. Do not delete H2 with settings and users: restore a known
backup or use an upstream-supported reset procedure. Ensure `.env` has no
`CHANGE_ME` and inspect interpolation with `docker compose config`.

### Wrong redirects, CORS errors, or links

`STIRLING_PDF_URL` must exactly match the browser origin: scheme, domain, and
optional port, with no path or trailing `/`. Run
`docker compose up -d --force-recreate` after changing it. Verify proxy `Host`
and `X-Forwarded-Proto`. This recipe supports root `/`, not a subpath.

### Uploads return 413 or disconnect

Align `STIRLING_PDF_UPLOAD_LIMIT_MB` with Nginx `client_max_body_size` or Caddy
`request_body max_size`. Check temporary space and RAM: processing can need
several times the source file size. Do not remove limits from a public service
without resource controls.

### OCR is missing a language

Inspect `data/tessdata` and logs. Every image variant may not bundle the required
traineddata; add only an official Tesseract tessdata file to the mounted
directory. Do not switch away from the standard image without rechecking
features and architecture support.

### H2 errors after an update

Do not run an old image over a new schema or rename
`stirling-pdf-DB-<schema-version>.mv.db`. Preserve the failed `configs`, restore
the old tag and complete pre-update archive through `restore.sh`. Without a
backup, stop the container and request upstream migration guidance.

### The reverse proxy returns 502

On the host, run `curl http://127.0.0.1:8080/api/v1/info/status`, then inspect
the upstream, timeouts, and proxy network namespace. Inside a container,
`127.0.0.1` refers to that proxy, not Stirling PDF on the host.
