Seafile is file sync and share built around libraries: each library is a
separate versioned repository that syncs to a desktop client, a phone, or a web
browser, and can be shared by link or by account. Files are stored as
deduplicated blocks rather than as a mirrored directory tree, which is what
makes syncing large collections and resuming interrupted transfers fast. A
library can be encrypted client-side, so the server never sees its contents.

This recipe runs pinned Seafile Community Edition 13.0.25 with MariaDB 10.11 and
a Valkey cache. The server keeps its configuration, logs, and the whole object
store in one volume; the three databases hold accounts, libraries, and metadata.
The web port binds to localhost, the SeaDoc editor, the notification server, and
the AI module are switched off because they are separate containers this recipe
does not ship.

<!-- coverage:security-assessment -->

### Security and recipe boundaries

The full application smoke test and practical backup and restore have passed on
amd64. The published image
supports amd64 only — the ARM builds upstream offers are marked testing — so the
manifest declares one architecture rather than promising a Raspberry Pi. The
administrator account, the MariaDB root password, the database password, the
cache password, and the JWT key all come from `.env`: give it mode 600, keep it
out of Git, and encrypt every archive, because the same file also decrypts the
backup. `SEAFILE_SERVER_HOSTNAME` and `SEAFILE_SERVER_PROTOCOL` are baked into
links, invitation e-mail, and client configuration at first start; changing the
domain later means editing the generated configuration inside the volume.
SAML and the advanced administration features belong to the Professional
Edition and are not part of this recipe.
