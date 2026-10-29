Wallabag saves readable copies of articles for later. Tags, favourites, reading progress, and annotations help turn a reading queue into a useful reference library. Official Android and iOS clients connect to a self-hosted server; browser extensions are available, while a standalone desktop application is not included.

For a shared bookmark library, compare collection and archiving features with Linkwarden and Karakeep. Wallabag focuses on the reading experience. A saved URL does not guarantee extraction from a paywall, a login-only page, a JavaScript-only site, or every publisher's layout.

This recipe runs Wallabag 2.6.15 with SQLite and separate volumes for the database/data and cached images. A short-lived initializer configures the database, applies migrations, and sets the administrator password before the web server can start. Registration remains disabled. Plan for one core, 512 MB RAM minimum (1 GB recommended), and 2 GB disk plus saved content; these are planning estimates, not a load benchmark.

The free self-hosted build supports password login and native two-factor authentication. TOTP, email delivery, mobile clients, and external reverse proxies are not configured or tested here. The application exposes an OAuth2 API; that does not provide OIDC or SAML login. A trusted-header login is not configured.

The application and deployment recipe are MIT licensed. This entry remains experimental pending wider deployment evidence. The reliable deployment level is unsupported: this single-server SQLite setup does not include a separate database, monitoring, or resource limits.

## Security assessment

<!-- coverage:security-assessment -->

The reviewed configuration rejects placeholder credentials, replaces the upstream default password before accepting HTTP requests, closes registration, and binds the web port to loopback. The deployment owns the `wallabag` administrator password from `.env`; a password change in the interface is replaced during initialization. Limit article submission to trusted users and restrict outbound traffic. Stored data and backups are not end-to-end encrypted. This configuration review is not a security audit.

Sources: [project and clients](https://wallabag.org/), [official documentation](https://doc.wallabag.org/), [Docker image and initialization](https://github.com/wallabag/docker), [2.6.15 release](https://github.com/wallabag/wallabag/releases/tag/2.6.15), [OAuth API](https://github.com/wallabag/wallabag/blob/2.6.15/doc/content/developer/api/oauth.md), [license](https://github.com/wallabag/wallabag/blob/2.6.15/COPYING.md).
