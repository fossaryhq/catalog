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
