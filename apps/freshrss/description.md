FreshRSS is a lightweight RSS and Atom aggregator for a personal feed or a small
trusted group. It groups sources, filters and labels articles, supports search,
OPML, and WebSub, while its Google Reader and Fever APIs work with third-party
Android, iOS, and desktop clients.

This recipe runs pinned FreshRSS 1.29.1 with PostgreSQL 18. Initialization is
deterministic: it creates a dedicated administrator with form authentication,
enables the API with a different password, selects the English interface and
production environment, and refreshes feeds twice per hour. Data, extensions,
and PostgreSQL use separate persistent volumes.

<!-- coverage:security-assessment -->

### Security and recipe boundaries

The full HTTP smoke test has passed on amd64, arm64, and armv7; backup and
restore remain untested in practice. The server fetches submitted feed URLs and can reach internal
addresses, so this recipe is only for trusted users. FreshRSS 1.29.1 has no
`INTERNAL_HOST_ALLOWLIST` option; the recipe neither invents it nor permits `*`.
Untrusted users require a separate outbound network policy. Web binds to
localhost, PostgreSQL has no published port, and proxy-header trust is disabled
by default.
