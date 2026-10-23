BookStack is a self-hosted wiki for knowledge you want other people to find and maintain. Books contain chapters and pages; shelves group related books. It suits a household handbook, a small team's documentation, or runbooks for a home server. Search, page revisions, attachments, and permissions help keep instructions usable as they grow.

Pages can use a visual editor or Markdown. The interface includes English and Russian, and readers use a browser on a desktop or phone; this recipe does not include native mobile or desktop apps. BookStack can replace the documentation side of Notion or Confluence, but it does not reproduce Notion databases, project boards, or all of Confluence's integrations.

This recipe pins BookStack v26.09.2 in the **community LinuxServer image**, together with MariaDB 11.4.13. BookStack's documentation links to third-party container options; the image is not published by the BookStack project. The app's `/config` volume holds uploads, private attachments, configuration, and themes; the separate MariaDB volume holds accounts, page content, revisions, and settings. Both belong in a backup, together with the original `APP_KEY`.

BookStack is MIT-licensed; the recipe is MIT-licensed separately. OIDC, SAML, and TOTP two-factor authentication are native features, but this recipe starts with local email/password authentication and does not configure an identity provider. Login through a proxy's user header is not part of this recipe.

The resource figures are planning estimates for a small installation: one CPU core, 1 GB RAM minimum, 2 GB recommended, and 5 GB disk before your documents and attachments. The images provide amd64 and arm64 variants; the runtime checks here cover amd64 only. A separate database and healthchecks are included, but monitoring and resource limits are not, so the reliable deployment level is partial.

Sources: [BookStack documentation](https://www.bookstackapp.com/docs/), [installation options](https://www.bookstackapp.com/docs/admin/installation/), [LinuxServer image](https://docs.linuxserver.io/images/docker-bookstack/), [authentication](https://www.bookstackapp.com/docs/admin/third-party-auth/), and [release v26.09.2](https://github.com/BookStackApp/BookStack/releases/tag/v26.09.2).

## Security assessment

<!-- coverage:security-assessment -->

The initial administrator credentials are public and must be replaced before network access. Keep the service behind HTTPS and the database private. Preserve the original APP_KEY with encrypted off-server copies of both data volumes: it protects encrypted application data, including MFA secrets. The recipe uses a third-party LinuxServer container. Image vulnerabilities have not been scanned here; functional smoke checks are not a security audit.
