Vaultwarden is a compact Rust implementation of the Bitwarden server API for
individuals, families, and small teams. It supports the official Bitwarden web
vault, mobile apps, desktop clients, and browser extensions, as well as
attachments, organizations, Send, and two-step login.

This recipe uses embedded SQLite and keeps the database, attachments, keys, and
configuration in a single local Docker volume. That is the whole appeal — and the
reason it does not claim the `reliable` level, which asks for a separate
database, monitoring, and resource limits.

> Vaultwarden is not associated with Bitwarden, Inc. Report server and
> compatibility issues to the Vaultwarden project, not official Bitwarden
> support.

<!-- coverage:security-assessment -->

### Security assessment

The container runs without `privileged`, host networking, or a Docker socket,
uses `no-new-privileges`, and binds its port only to `127.0.0.1`. Registration
and invitations are disabled by default. `/admin` is unavailable because the
recipe does not set `ADMIN_TOKEN`.

Treat this container as the most valuable thing on the server. Serve it over
HTTPS only, turn on two-factor authentication for every account, apply image
updates quickly, and encrypt any copy that leaves the machine — a backup archive
here is the vault.

If you do need `/admin`, follow the upstream guide: generate an Argon2id hash of
the token, keep it out of Git, and restrict the path at the reverse proxy or
behind a VPN.
