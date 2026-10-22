Mealie is a self-hosted recipe manager for households and small groups. Save recipes by importing a URL or writing them yourself, organize them into cookbooks, plan meals, and build a shared shopping list. This recipe runs Mealie's official container with SQLite and keeps its database, images, and uploaded files together in one persistent volume. It suits a home kitchen; the recipe does not include PostgreSQL, email, or AI providers.

<!-- coverage:security-assessment -->

### Security assessment

The recipe keeps the web port on `127.0.0.1`, disables open signup, and runs
without privileged mode, host networking, or Docker socket access. The only
container volume holds both the SQLite database and uploaded data; include it in
off-server backups and protect those archives.

Mealie documents the initial login (`changeme@example.com` / `MyPassword`). It
must be changed over loopback before the service becomes reachable to other
users. URL imports fetch pages from the server and can expose internal services
to trusted users who can trigger imports, so keep access limited and isolate the
container where practical. When using a reverse proxy, Mealie's default
`HOST_IP=*` trusts forwarded headers from any connecting source; restrict it to
the proxy address or network and block direct untrusted access.

The configuration has not yet had an image vulnerability scan; the stored scan
status remains unknown.
