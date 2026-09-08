### Login does not go through: the form accepts the password and returns to the login screen

n8n does not send the session cookie over plain HTTP unless the address is
`localhost`. Check how you open the UI. Through an SSH tunnel on `localhost`
everything works with the defaults. For access by IP inside a trusted network,
set `N8N_SECURE_COOKIE=false` in `.env` and recreate the container:

```bash
docker compose up -d
```

The proper fix for outside access is HTTPS behind a reverse proxy, not a
disabled flag.

### The n8n container never becomes healthy

```bash
docker compose ps
docker compose logs --tail=200 n8n
```

The first start takes longer: the database migrations are running. If the logs
show `ECONNREFUSED` against `database`, check the state of PostgreSQL — n8n only
starts after its healthcheck passes:

```bash
docker compose logs --tail=100 database
```

### Credentials stopped opening after a migration

This is almost always a mismatched `N8N_ENCRYPTION_KEY`. Workflows and history
travel in the database dump, but service passwords are encrypted with the key,
which lives in `.env` and in `config` inside the `n8n-data` volume. Verify that
the key is the same:

```bash
grep N8N_ENCRYPTION_KEY .env
docker compose exec n8n cat /home/node/.n8n/config
```

If the old key is lost, the credentials cannot be recovered and have to be
entered again.

### An external service's webhook never arrives

Open the Webhook node and look at the Production URL. If it says `localhost`,
`N8N_WEBHOOK_URL` is not set:

```bash
grep -E 'N8N_WEBHOOK_URL|N8N_PUBLIC_HOST|N8N_PROTOCOL' .env
```

Fill them in with the external address and run `docker compose up -d`. Remember
that a node's test URL only lives while the editor is open, and the production
one appears after the workflow is activated.

### The database grows and the disk fills up

The execution history is pruned according to `N8N_EXECUTIONS_MAX_AGE_HOURS`.
Check the size:

```bash
docker compose exec -T database psql -U n8n -d n8n \
  -c "select pg_size_pretty(pg_database_size('n8n'))"
```

Lower the retention in `.env` and recreate the container. Also check individual
workflows: each one can stop saving successful executions.

### A workflow does not run on schedule

The Schedule and Cron nodes follow `GENERIC_TIMEZONE`, which comes from `TZ` in
`.env`. Check the zone inside the container:

```bash
docker compose exec n8n date
```

And make sure the workflow is activated with the toggle in the editor: a saved
but inactive workflow never runs on schedule.

### The Code node fails with a file or network access error

In this recipe the code runs inside the n8n container, without the external
sandboxed runner. Some operations are limited by the file system access
settings. Do not weaken those limits on an instance whose editor several people
can reach: the Code node runs arbitrary code with n8n's privileges.
