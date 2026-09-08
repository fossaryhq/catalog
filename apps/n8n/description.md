n8n is a workflow automation builder: a workflow is assembled on a canvas from
nodes, where each node receives data from the previous one, transforms it, and
passes it on. Runs are triggered by a schedule, a webhook, an event in an
external service, or manually from the editor. There are branches, loops,
retries, and separate error-handling paths.

More than five hundred ready-made integrations ship with it — email, messengers,
databases, CRMs, cloud storage, LLM providers. Anything missing is covered by a
generic HTTP request node or a node with your own JavaScript and Python code.
Unlike Zapier and Make, both the workflows and the credentials for those
services stay on your own server.

The recipe runs n8n together with PostgreSQL: on SQLite the execution history
quickly runs into write locks. The panel is published on `127.0.0.1:5678` only.

> No isolated smoke test has been run yet, so this published recipe remains
> unverified.

<!-- coverage:security-assessment -->

### Security assessment

The containers run without `privileged`, host networking, or the Docker socket,
and with `no-new-privileges`. PostgreSQL is not published to the host at all,
and the n8n port is bound to `127.0.0.1`.

What makes n8n special is that the instance accumulates access to every service
you connect. Those credentials sit encrypted in the database, and the key comes
from `N8N_ENCRYPTION_KEY`. A database dump together with `.env` is equivalent to
the keyring for your mail, CRM, and cloud storage at once, so the archives must
be stored and transferred as secrets.

The second risk is code execution. The Code node runs arbitrary JavaScript and
Python, and community nodes install npm packages into the instance. All of it
runs with the privileges of the n8n process inside its container. The official
sandboxed runner isolates such code but requires privileged Docker-in-Docker, so
it is not part of this recipe: grant editor access only to people you trust to
run code on the server.

Third, webhooks and the editor live on the same port. Publishing a webhook to
the internet also exposes the control panel, so HTTPS and a strong owner
password are mandatory.
