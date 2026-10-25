# Audiobookshelf

Stream your own DRM-free audiobooks and podcasts from a private server. Separate accounts retain listening position, bookmarks and collections; library permissions keep a regular listener away from libraries they were not granted.

This is a media library server, including an audiobook-focused alternative to managing your files in Plex. It does not replace a commercial content subscription or supply licensed books. Android and iOS clients and native OIDC are available upstream; this recipe verifies the browser and local accounts.

The pinned container runs as UID/GID 1000 with a read-only root, no capabilities and a single persistent `/data` volume. The volume includes configuration, SQLite, signing material, metadata, covers, audiobook files and podcasts. A dedicated tools service calls the native first-user API; it is not a background identity provider.

## Verification

On 2026-10-25, amd64 smoke exercised native setup, restricted-user access, scanning, real audio range delivery, progress/bookmark/collection and recovery after deleting the volume. It also rejected incomplete backups before mutation and preserved a stopped service during backup. Three real screens per locale use original narrated samples and original covers. ARM64, mobile apps, OIDC, internet podcast fetching, external metadata and production TLS were not tested.

<!-- coverage:security-assessment -->
Security assessment (2026-10-25): loopback, UID 1000 process, read-only root, no host/Docker socket access, and explicit initial bootstrap. Protect first setup and the entire private data volume. This is a configuration review, not a vulnerability scan.
