Forgejo is a free software Git service for teams and personal projects. It
combines repositories, code review, issues, projects, wikis, releases, and a
package registry without handing source code to an external platform.

This recipe runs the pinned Forgejo 16.0.5 rootless image with PostgreSQL 17.
The web UI and built-in SSH server bind to localhost, and open registration is
disabled. Forgejo Actions and a runner are intentionally out of scope.

<!-- coverage:security-assessment -->

### Security and exposure

The full smoke test has passed on amd64; arm64 has not been re-tested for this version; backup and restore remain
untested in practice. Public web access requires an HTTPS reverse proxy. Only
expose SSH after configuring the administrator, keys, and firewall. Repositories,
attachments, and configuration live under `/var/lib/gitea`; PostgreSQL stores
the database separately.
