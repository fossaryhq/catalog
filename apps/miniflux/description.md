Miniflux is a deliberately small feed reader: one Go binary, one PostgreSQL
database, no plugins, no recommendation engine, and no account on somebody
else's server. It reads RSS, Atom, JSON Feed, and RDF, fetches the full article
text when a feed only ships an excerpt, keeps entries readable offline in the
browser, and exposes the Google Reader and Fever APIs so existing mobile
readers can sync against it.

This recipe runs pinned Miniflux 2.3.3 with PostgreSQL 18. The application
itself stores nothing on disk — feeds, entries, icons, sessions, and API keys
all live in the database, so a single dump is the whole backup. The web port
binds to localhost and PostgreSQL is not published at all.

<!-- coverage:security-assessment -->

### Security and recipe boundaries

The full application smoke test has passed on amd64 and arm64, and practical
backup and restore have passed on amd64.
Miniflux fetches arbitrary URLs on a schedule, so treat the poller as an
outbound HTTP client with the reach of its network — put an egress policy in
front of it if the instance is shared with people you do not fully trust.
Passwords are the only credential the recipe sets up; both the administrator
password and the PostgreSQL password sit in `.env`, which must be mode 600 and
must never enter Git. `TRUSTED_REVERSE_PROXY_NETWORKS` is limited to loopback,
so forwarded client-IP and proxy-authentication headers are ignored until an
operator deliberately trusts the Docker bridge network. The recipe does not set
up OAuth2/OIDC or passkeys; both are supported upstream and are configured
after the first sign-in.
