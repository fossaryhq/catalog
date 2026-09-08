Linkwarden is a bookmark manager and web archive for one user, a family, or a
small team. It organizes links into collections, adds tags, provides full-text
search, and preserves pages and documents for reading after the original
disappears. Shared collections, a browser extension, and official Android and
iOS clients are available.

This recipe runs pinned Linkwarden v2.16.2 with PostgreSQL 16 and Meilisearch
1.13.3. Preserved content, the database, and the search index each use persistent
storage. The web port binds to localhost, internal services are not published,
and preserved HTML is served from a separate origin.

<!-- coverage:security-assessment -->

### Security and recipe boundaries

The full HTTP smoke test has passed on amd64; backup and restore remain untested
in practice. A headless browser fetches untrusted URLs and can consume substantial
CPU, RAM, and disk. Private-network access and insecure TLS are forced off, but
that does not replace an egress firewall for untrusted users. Preserved HTML is
isolated on a separate origin without shared cookies. Registration ships open so
that the first account can be created, and nothing closes it afterwards: set
`NEXT_PUBLIC_DISABLE_REGISTRATION=true` and recreate the container as soon as
you have signed up, or anyone who reaches the URL can register.
