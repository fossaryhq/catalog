## The container exits or stays unhealthy

Check the settings and the required environment variables:

```bash
docker compose config
docker compose ps --all
docker compose logs --tail=200 node-red
```

`NODE_RED_ADMIN_PASSWORD_HASH` must be a bcrypt hash, not a plain password.
Regenerate it with `node-red admin hash-pw`; then recreate the container.

## The editor returns 401 or login fails

Confirm the configured user and hash are present, then force a recreate:

```bash
grep '^NODE_RED_ADMIN_USERNAME=' .env
grep '^NODE_RED_ADMIN_PASSWORD_HASH=' .env
docker compose up -d --force-recreate
```

Do not remove `adminAuth` from `config/settings.js` to regain access on a public
server. Generate a new password hash instead. Changing the credential secret is
unrelated to editor login and makes saved credentials unreadable.

## Port 1880 is already in use

Change `NODE_RED_PORT` in `.env`, recreate the service, and update the reverse
proxy upstream. Keep the localhost bind:

```bash
docker compose up -d
docker compose port node-red 1880
```

## A flow does not deploy or a node is missing

Open the sidebar debug panel and inspect the runtime logs:

```bash
docker compose logs --tail=200 node-red
```

Install only reviewed nodes through the palette manager, then export the flow
before changing it. A community node is executable code inside the container;
removing it can leave dependent flows invalid.

## Credentials cannot decrypt after restore

The restored `flows_cred.json` requires the exact
`NODE_RED_CREDENTIAL_SECRET` that encrypted it. Put the saved secret back in
`.env`, recreate the container, and retry. If the old secret is unavailable,
delete the broken credentials only after exporting non-secret flows and enter
credentials again; no recovery bypass exists.
