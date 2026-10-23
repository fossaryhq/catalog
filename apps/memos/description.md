## Short notes that stay on your server

Memos is a web notebook for Markdown, checklists, tags, search, and attachments. It suits a personal knowledge log, household references, reading notes, and small shared spaces. It replaces the short-note workflow of Google Keep; it is not a full office suite. The browser interface supports English and Russian, light and dark themes, and installable web-app use. Third-party native clients are outside this recipe.

The official `neosmemo/memos:0.31.0` image uses SQLite and local attachment storage in one persistent volume. Plan for one CPU core, 256 MB RAM (512 MB recommended), and 1 GB plus attachments; these are planning estimates, not a load benchmark. amd64 was exercised; arm64 is available in the image but untested here.

## Privacy and authentication

<!-- coverage:security-assessment -->

Image CVEs have not been scanned; the manifest records this as unknown. SMTP, SSO, remote storage, and reverse-proxy integration were not exercised.

The recipe mounts upstream-supported deployment configuration: instance access is PRIVATE and public registration is disabled. The first visitor can still create the administrator. Complete that step through loopback or an SSH tunnel before opening the HTTPS proxy. Administrators add later accounts.

Private notes are not end-to-end encrypted. Instance administrators can read and manage private notes, and a share token can grant access to its holder. Protect the volume, restrict administrator accounts, and encrypt off-server backups. OAuth2 providers, including providers using OpenID scopes, are supported natively; this recipe configures password login only. It does not supply SAML, native two-factor authentication, or proxy-header login.

## Operations and limits

Backups stop writers and preserve the complete data volume: SQLite, local attachments, and persistent instance secrets. A personal export omits other users and instance configuration and is not a server backup. The full amd64 smoke test creates an administrator and a private memo, uploads a file, checks anonymous access is refused, removes the volume, and restores usable notes and file bytes.

Memos is MIT licensed. Version 0.31 changes APIs, removes RSS, and expands administrator access; read release notes before upgrading. Keep a pre-upgrade archive and matching version for rollback. This 0.x recipe uses a 30-day recheck interval because API and permission behavior can change between minor releases.

Sources: [documentation](https://usememos.com/docs), [v0.31.0 notes](https://github.com/usememos/memos/releases/tag/v0.31.0), [deployment configuration](https://github.com/usememos/memos/blob/v0.31.0/docs/configuration-provisioning.md), [license](https://github.com/usememos/memos/blob/v0.31.0/LICENSE). The local SVG mark comes from the [official favicon](https://usememos.com/brand/favicon.svg), recolored for the catalog tile.
