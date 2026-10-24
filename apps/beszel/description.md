Beszel keeps a small historical view of server resources: CPU, RAM, swap, disk usage and traffic. Agents supply the measurements; the hub stores accounts, access assignments, alert settings and history in local SQLite databases. It suits household servers and small infrastructure where a compact resource dashboard is useful.

This recipe installs the hub, not agents on every machine. Add each monitored system through the native interface and deploy a matching pinned agent on that system. Docker, GPU, SMART, ZFS and systemd integrations need separate permissions and configuration. The included smoke uses a real isolated agent without host networking or Docker socket; its readings are sandbox measurements.

The hub creates both an application administrator and a PocketBase superuser from the supplied email/password only when the database is new. Self-registration is closed. Upstream supports OIDC, email-OTP MFA and trusted-header authentication, but the recipe does not configure them. SMTP is required for email-OTP MFA.

The browser interface is built in. Android/iOS and macOS clients listed by the official documentation are independent third-party projects and were not tested here. Review their licenses and credential handling before connecting them.

For users of Netdata Cloud, Beszel covers local server-resource dashboards and history. Its monitoring scope and integrations differ; no price saving is claimed without verified current terms.

<!-- coverage:security-assessment -->
Security assessment (2026-10-24): loopback HTTP, non-root process, read-only container root, closed signup and no host/Docker access. Protect the hub's SSH identity, the PocketBase admin interface and every agent separately. This configuration review is not a vulnerability scan.

Sources: [hub installation](https://beszel.dev/guide/hub-installation), [agents](https://beszel.dev/guide/agent-installation), [environment](https://beszel.dev/guide/environment-variables), [security](https://beszel.dev/guide/security), [OIDC](https://beszel.dev/guide/oauth), [mobile](https://beszel.dev/guide/third-party-integrations/mobile-apps), [desktop](https://beszel.dev/guide/third-party-integrations/desktop-apps).
