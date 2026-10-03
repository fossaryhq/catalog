Node-RED lets you assemble automation as a flow of visible nodes. An incoming
webhook, timer, MQTT message, HTTP request, database query, or a small
JavaScript function can feed the next step. It is especially useful for smart
home and device work, but it also makes a compact self-hosted alternative for
API glue and scheduled jobs.

This recipe runs one official Node-RED container with no database. Its persistent
volume holds flows, installed nodes, settings, and encrypted credentials. The
editor requires a locally configured password and is bound to localhost by
default; put it behind one of the supplied HTTPS reverse-proxy examples before
making it public.

Node-RED is a better fit than n8n when you want direct control of event and IoT
flows, custom JavaScript, and a small runtime. n8n has more ready-made SaaS
connectors and a more guided execution history. Neither product makes an
unreviewed community node safe: review packages before installing them.

<!-- coverage:security-assessment -->

### Security assessment

This recipe does not use privileged mode, host networking, or the Docker
socket, and applies `no-new-privileges`. The editor is bound to `127.0.0.1` by
default, so it is not directly reachable from the network.

The editor is nevertheless a high-trust control plane. Anyone with editor
credentials can deploy arbitrary JavaScript through Function nodes and install
third-party palette packages; both run with the container's permissions. Give
editor access only to people who are allowed to run code on the server, and
review community nodes before installing them.

Flows can hold API tokens and passwords. They are encrypted with
`NODE_RED_CREDENTIAL_SECRET`, but an attacker who obtains both that secret and
the persistent volume or backup can decrypt them. Treat `.env` and backups as
password-equivalent secrets. If you publish the editor or webhooks, place them
behind HTTPS, use a unique strong password, and avoid exposing port 1880
directly.
