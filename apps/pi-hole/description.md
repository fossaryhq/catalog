Pi-hole is a DNS resolver with blocklists. Put it on a trusted network and set
it as the DNS server in your router: requests for advertising and tracking
domains are blocked for phones, TVs, and other devices without browser add-ons.
It suits a home network or a small private network whose administrator can
control DHCP or the DNS settings of each client. It is a self-hosted alternative
to services such as NextDNS and AdGuard DNS.

The web interface shows recent queries, blocked requests, clients, and list
management. Its interface is currently available in English. Pi-hole can also
serve local DNS records. DNS filtering cannot
remove ads served from the same domain as desired content, and clients that
override the network DNS with their own encrypted resolver can bypass it.

This recipe runs one official container. Its `pi-hole-data` volume holds
`pihole.toml`, Gravity and query databases, and list data. The DNS port starts
on `127.0.0.1`; choose a specific trusted LAN or VPN address when ready to serve
other devices. The web panel remains on the host's loopback address.

<!-- coverage:security-assessment -->

### Security assessment

The container uses Docker's bridge network without privileged mode, host
networking, or access to the Docker socket. Only port 53 is needed for DNS;
the built-in DHCP and NTP services are not exposed. The official image's own
healthcheck checks DNS service readiness.

Do not bind DNS to a public interface: an open resolver can be used in
amplification attacks. A Pi-hole administrator can inspect the domains queried
by every client, so keep the web panel behind its password and HTTPS when
accessing it remotely. The `.env` password and backup archives are sensitive.
See the [official Docker guide](https://docs.pi-hole.net/docker/) and
[configuration reference](https://docs.pi-hole.net/docker/configuration/).
