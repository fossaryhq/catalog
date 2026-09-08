AdGuard Home is a DNS server that sits between the devices on your network and
the internet and drops requests to advertising, tracking, and malicious domains.
Because filtering happens at the network level, it covers TVs, set-top boxes,
smart speakers, and guest devices where a browser extension cannot be installed.

Beyond filtering it works as an ordinary resolver: it supports DNS-over-HTTPS
and DNS-over-TLS upstreams, caches answers, keeps a query log, and shows
per-client statistics. Individual rules and schedules can be assigned to
specific devices.

The recipe runs a single container with two Docker volumes and the control panel
on `127.0.0.1:3000`. The built-in AdGuard Home DHCP server is not included: it
requires host networking or macvlan, which is incompatible with the isolated
Compose network.

<!-- coverage:security-assessment -->

### Security assessment

The container runs without `privileged`, host networking, or the Docker socket,
and with `no-new-privileges`. The control panel is published on `127.0.0.1`
only — a DNS administrator sees the browsing history of the entire network, and
the panel must never be exposed without HTTPS and authentication.

The main risk is specific to DNS: a server listening on port 53 on a public
interface becomes an open resolver and gets abused in DNS amplification attacks.
That is why `ADGUARD_DNS_BIND` defaults to `127.0.0.1`, and the guide tells you
to set a specific LAN interface address rather than `0.0.0.0`. On a VPS, DNS
access should be granted over a VPN only.

The second risk concerns the data itself: the query log stores the domains every
device on the network opens. Retention and client anonymization are configured
in the query log settings.
