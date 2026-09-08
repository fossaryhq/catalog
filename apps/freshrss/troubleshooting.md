### FreshRSS does not become healthy

```bash
docker compose ps
docker compose logs --tail=200 freshrss database
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q freshrss)"
docker compose exec freshrss cli/health.php
```

Check the three required distinct secrets, PostgreSQL health, free disk, and
first-run errors. Passwords must be alphanumeric without spaces or shell
characters. If an empty installation failed before completion, inspect logs and
only then remove the empty volumes and retry; never delete working data.

### Wrong redirects, URL, or WebSub callback

`FRESHRSS_BASE_URL` must exactly match the public URL: scheme, host, optional
port and path, without a trailing `/`. It applies only during installation; for
an existing instance, change `base_url` in data `config.php` using upstream's
documented procedure, then recreate the container. A dedicated subdomain is
simpler and more reliable than a subpath.

### An API client cannot sign in

Ensure the client uses `FRESHRSS_ADMIN_API_PASSWORD`, not the web form password,
and the Google Reader endpoint on the same HTTPS host. Verify that Nginx forwards
`Authorization`; Caddy and Traefik preserve it by default. FreshRSS does not need
WebSockets.

### Feeds on internal addresses are reachable

This is FreshRSS 1.29.1 behavior, not a recipe error. Do not add a wildcard
internal-host allowlist: this version has no such supported variable, and
allowing every address would create a false sense of protection. For untrusted users, block
container egress to loopback, RFC1918, link-local, and cloud metadata addresses
with network/firewall policy, or isolate FreshRSS on a dedicated network.

### The client IP is wrong behind a proxy

The safe `FRESHRSS_TRUSTED_PROXY=0` disables forwarded client-IP handling. If an
exact client IP is required, trust only the final proxy IP/CIDR and secure the
connection to FreshRSS. A broad range permits spoofed IP and
`Remote-User`/`X-WebAuth-User` headers, potentially granting administrator access.

### An extension breaks the page or CSP

Disable the third-party extension through the UI or restore `extensions` from a
backup. Do not hide the problem by suppressing the warning or overriding
`Content-Security-Policy` at the reverse proxy; FreshRSS emits its own CSP.

### The reverse proxy returns 502

On the host, run `curl -I http://127.0.0.1:8080/`. Inspect the upstream, firewall,
and proxy namespace. Inside a container, `127.0.0.1` refers to the proxy itself,
not FreshRSS on the host; use a host gateway or a shared private network.
