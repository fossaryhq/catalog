Gatus turns a YAML file into scheduled availability checks and a status
dashboard. It can probe HTTP responses, TCP and UDP ports, DNS, ICMP, SSH,
certificates, domain expiry, and multi-step API suites, then evaluate explicit
conditions instead of treating any response as success.

It suits operators who want monitoring configuration in version control and do
not need a form-driven editor. The dashboard shows response history and
incidents, while alert providers cover email, chat systems, webhooks, and
on-call services. This recipe uses the built-in SQLite storage so the check
history survives restarts without a separate database.

> The dashboard edits no endpoints. Change `config/config.yaml`, review the
> diff, and restart Gatus; this is the main difference from Uptime Kuma's
> UI-first workflow.

<!-- coverage:security-assessment -->

### Security assessment

The recipe publishes Gatus on `127.0.0.1`, enables Basic Auth from `.env`, sets
`no-new-privileges`, and grants no capabilities, host networking, or Docker
socket. Public access belongs behind an HTTPS reverse proxy.

Gatus is an outbound probe by design. Anyone who can change `config.yaml` can
make requests to addresses reachable from its container network, including
private services. Limit write access to the recipe directory. The official
image also runs as root by default; the recipe narrows what that process can
reach on the host, but does not change its container user.
