Homepage is a configurable landing page for a home server. Group services, keep useful bookmarks, search them with Quick Launch, and add optional service widgets. It suits operators who prefer YAML configuration over a database-backed portal.

The starter links point to this dashboard and official public documentation. Replace them with your own service URLs in `config/services.yaml`; they do not install the linked applications. The dashboard complements service monitoring rather than replacing it.

As of v2, upstream includes password or OIDC authentication. This recipe enables one shared password and a random session secret. OIDC is available but not configured. There are no separate user permissions, native SAML or native MFA in this recipe. An identity provider may add MFA externally.

All dashboard YAML, custom CSS/JavaScript and logs live in the mounted configuration directory. No database, Docker socket, Kubernetes credentials, API keys or cloud account are required. Resource widgets see the container's environment. Search can contact the provider you select when you submit a query.

Homepage can replace the service-link part of start.me for a homelab, but does not reproduce its cloud collaboration features. Its upstream repository includes GPL version 3; the image label still says Apache-2.0, so use the repository LICENSE as the recorded source for this page.

Official sources: [installation and authentication](https://gethomepage.dev/installation/), [configuration](https://gethomepage.dev/configs/), [Docker](https://gethomepage.dev/installation/docker/), [v2.7.0 source](https://github.com/gethomepage/homepage/tree/v2.7.0).

<!-- coverage:security-assessment -->
Security assessment (2026-10-24): password gate enabled, loopback bind, non-root process and no Docker socket. Public access still needs HTTPS and edge login protection. This is a configuration review, not an image vulnerability scan.
