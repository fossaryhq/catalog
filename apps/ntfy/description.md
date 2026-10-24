ntfy is a publish/subscribe notification server. A backup job, availability check, or household script sends an HTTP request to a topic; subscribed clients receive the message through the browser or a mobile app. Priorities, titles, tags, and attachments help a short notification carry enough context to act.

## Where it fits

Use it for personal monitoring and automation when you want to operate the notification server yourself. It can cover everyday Pushover-style publish/subscribe workflows. You take responsibility for HTTPS, accounts, uptime, storage, and the delivery path a phone or browser uses; it does not turn a notification cache into a permanent archive.

This recipe runs the official pinned image as UID/GID 1000 with a read-only root filesystem. An initialization helper prepares one named volume. The server keeps SQLite message/auth databases and attachment files together, requires login, disables signup, and denies topic reads and writes without an explicit permission. The administrator comes from a private declarative bcrypt entry before requests are served.

## Data and delivery limits

Messages and attachments are cached for seven days. Accounts, access tokens, topic ACLs, and account subscriptions/settings persist in the same volume; the web client also keeps a local IndexedDB cache. Server backup does not copy a browser profile. A restored attachment retains its original expiration time.

**Topic authentication does not make attachment URLs private.** Anyone who knows an attachment URL can download its bytes without login. Treat the URL as a bearer secret, encrypt sensitive attachments before uploading, and avoid putting passwords or recovery keys in notification bodies. Data at rest is not end-to-end encrypted by this recipe.

The smoke checks a live HTTP subscriber, actual publishing, cached reads, accounts, token ACLs, attachment bytes, and recovery after deleting the volume. It also verifies that an attachment is downloadable without login when its URL is known. No physical phone or background browser delivery was tested.

## Clients and optional services

The browser and official Android/iOS clients are available upstream. An open browser can receive messages directly. Android can use direct server connections; Firebase is a separate delivery path. Instant iOS notifications from a self-hosted server need upstream polling, normally through ntfy.sh, while closed-browser Web Push needs VAPID keys and browser push services. This recipe configures none of those optional relays, SMTP, phone calls, or external storage. Read their connectivity and privacy requirements before enabling them; do not assume the CPU/server smoke proves mobile background delivery.

<!-- coverage:security-assessment -->

## Security and maintenance

Keep the web port on loopback or behind a trusted VPN/proxy. Publish only through HTTPS, protect .env, grant automation accounts only their required topics, and encrypt external backups. ntfy does not provide native OIDC, SAML, MFA, or trusted-user-header login in this version. Forwarded client-IP trust stays off, so proxy requests share the proxy's rate limit.

The declarative administrator hash is authoritative on every startup. Rotate it deliberately and preserve a matching environment during restore. A regular account and token created through the native CLI/API are stored in SQLite and are included in backup.

Upstream is dual licensed under Apache-2.0 and GPLv2; the recipe is MIT. The catalog icon comes from the upstream mask asset under the Apache-2.0 option; its license is retained in ASSET-LICENSES.md.

Sources: [v2.33.1](https://github.com/binwiederhier/ntfy/releases/tag/v2.33.1), [configuration and access control](https://docs.ntfy.sh/config/), [publishing](https://docs.ntfy.sh/publish/), [subscriptions](https://docs.ntfy.sh/subscribe/), [license](https://github.com/binwiederhier/ntfy/tree/v2.33.1).
