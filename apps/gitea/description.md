Gitea is an open-source Git service for small teams and personal projects. It
combines repositories, code review, issues, projects, wikis, releases, package
registries, and built-in CI/CD support without handing code to an external
platform.

This recipe runs the pinned official Gitea 28.1.0 image with PostgreSQL 17.11.
The web UI and built-in SSH server bind to localhost, and open registration is
disabled. Gitea Actions and a runner are intentionally out of scope.

<!-- coverage:security-assessment -->

### Security and exposure

The full smoke test has passed on amd64; arm64 has not been re-tested for this version; backup and restore remain
untested in practice. Public web access requires an HTTPS reverse proxy. Only expose
SSH after configuring the administrator, keys, and firewall. Repositories,
attachments, and configuration live under `/data`; PostgreSQL stores the
database separately.
