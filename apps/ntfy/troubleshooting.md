## Startup or healthcheck failure

Run `docker compose config --quiet`, `docker compose ps`, and `docker compose logs --tail=100 ntfy permissions`. Confirm the permissions helper exited successfully and UID/GID 1000 can write the volume. `/v1/health` must return healthy true. An invalid bcrypt entry prevents startup: generate it with the pinned image's `user hash` command and single-quote it in .env. Do not paste plaintext or an unquoted dollar-containing hash.

## Login, token, or topic permission denied

Sign in as the name before the first colon in NTFY_AUTH_USERS. Its hash is declarative and reapplied at startup; changing an old plaintext password note or using a CLI password command on a provisioned user does not rotate it. Create a normal account for automation, inspect `docker compose exec ntfy ntfy user list`, and grant only required topics with `ntfy access`. A regular user's token inherits that user's ACLs. A topic name is not an access credential.

## Messages arrive in the open page but not in the background

The server smoke proves HTTP delivery, not OS push. Check the client's server URL, login, network reachability and notification permissions. Browser Web Push needs HTTPS/VAPID and browser push services; self-hosted iOS instant push needs upstream polling; Android direct connections have their own background/battery requirements. Those integrations are not configured by this recipe. Use the upstream client-specific setup instead of disabling authentication.

## Broken attachment URL or unexpected download without login

Match NTFY_URL to the exact externally reachable origin, recreate ntfy, and test a newly uploaded sample. Attachment URLs deliberately work as bearer links without login; topic ACLs do not protect a leaked link. Encrypt sensitive files before upload. Both messages and attachments expire after seven days, and restore keeps original timestamps. Check disk space and the 1 GB total / 15 MB per-file limits.

## Proxy disconnects or rate limits

Preserve websocket upgrades and streaming HTTP responses, disable proxy buffering and use long read timeouts. With forwarded-IP trust disabled, requests share the proxy IP's rate limit. Keep host port 8083 private; a containerized proxy cannot use its own 127.0.0.1 to reach a host service. Do not trust arbitrary X-Forwarded-For values to bypass rate limiting.

## Missing data after restore

Check that the complete archive includes both SQLite databases and attachments, and compare configuration.env manually before restoring. A mismatched NTFY_AUTH_USERS entry overrides restored administrator credentials. Keep the current volume and safety backup while investigating; expired cache data does not become fresh after recovery. Re-test a message, sample attachment, regular user and scoped token.

Sources: [configuration](https://docs.ntfy.sh/config/), [publishing](https://docs.ntfy.sh/publish/), [subscriptions](https://docs.ntfy.sh/subscribe/).
