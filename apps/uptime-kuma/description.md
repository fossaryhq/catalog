Uptime Kuma watches things and tells you when they stop working. It checks
HTTP(S) endpoints, TCP ports, DNS records, ping, and TLS certificate expiry, then
sends a notification through Telegram, email, a webhook, or any of the ninety-odd
other providers it ships with.

It suits a home server, a side project, or internal infrastructure — anywhere you
want to know about an outage before someone else reports it. A small instance
needs no separate database: everything lives in one local Docker volume. Public
status pages and a container healthcheck are built in, and the interface is
translated into more than forty languages.

> This recipe deliberately leaves the Docker socket unmounted. Monitoring
> websites and ports does not need it, and handing a container direct socket
> access hands it the host.

<!-- coverage:security-assessment -->

### Security assessment

The recipe runs without `privileged`, without host networking, and without the
Docker socket. It sets `no-new-privileges` and publishes its port on `127.0.0.1`
only, so anything public goes through an HTTPS reverse proxy.

One risk appears only if you later add Docker API access to monitor containers.
Put a restricted socket proxy in front of it rather than mounting
`/var/run/docker.sock` into the container: read access to the socket is
equivalent to root on the host.
