Karakeep collects links, text notes, images, and PDFs in a private library. Lists, tags, favourites, and full-text search make it useful for research, household references, and reading later. Official Android and iOS apps and browser extensions can send items to the server; a standalone desktop client is not bundled.

Compared with Linkwarden, evaluate how each handles lists, saved formats, sharing, and search. Karakeep also keeps plain text notes alongside links. Saving a URL is not a guarantee that a paywall, login page, or bot-protected site can be archived.

This recipe runs the official app with SQLite, Meilisearch 1.41.0, and a separate headless browser. Allow two cores, 2 GB RAM minimum (4 GB recommended), and 10 GB disk plus saved content. Browser jobs can exceed those estimates; monitor disk and memory. The reliable deployment level is unsupported: this single-server recipe has no external database, monitoring, or resource limits.

Password login and native OIDC are available upstream; this recipe configures password login only. It does not configure SAML, a second factor, trusted-header login, SMTP, or an AI provider. AI tagging is optional, and bookmark capture and search work without an API key. Backups are not end-to-end encrypted.

The application is AGPL-3.0 licensed; the deployment recipe is MIT licensed. See the upstream licence before modifying and serving the software. This entry is experimental until wider deployment evidence exists.

Sources: [features and clients](https://karakeep.app/), [configuration](https://docs.karakeep.app/configuration), [security considerations](https://docs.karakeep.app/administration/security-considerations), [release](https://github.com/karakeep-app/karakeep/releases/tag/v0.34.1), [licence](https://github.com/karakeep-app/karakeep/blob/v0.34.1/LICENSE).

## Security assessment

<!-- coverage:security-assessment -->

The reviewed configuration keeps registration closed and internal service ports private. Basic SSRF checks and container isolation do not make hostile crawled content safe. Use trusted accounts and an independent egress policy. This review is not a security audit.
