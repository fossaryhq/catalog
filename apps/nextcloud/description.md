Nextcloud is cloud storage that lives on your own server. Files sync with a
computer and a phone, folders open to colleagues by name or through a public
link, and on top of the files sits the familiar set: calendar, contacts, notes,
tasks, and collaborative document editing. It fits a family, a small team, or
anyone leaving Google Drive and Microsoft 365.

What separates it from plain file synchronisation is permissions and
collaboration. There are accounts, groups, quotas, link expiry dates, passwords
on public folders, and an activity log. Nextcloud is not "a folder on several
devices" but a server with users.

The recipe brings up four containers: Nextcloud itself, PostgreSQL, Valkey for
file locking and caching, and a separate container for background jobs. Without
the last one Nextcloud falls back to AJAX mode and only runs maintenance while
someone has the interface open. The code, apps, and `config.php` live in a
Docker volume; user files live in a host directory.

The `reliable` level is declared partial: the database is a separate service and
there are healthchecks and a background worker, but the recipe sets no resource
limits and adds no external monitoring.

> Nextcloud takes more maintenance than the other apps in this catalogue.
> Upgrades go one major version at a time, and after each one it is worth
> checking the security warnings page.

<!-- coverage:security-assessment -->

### Security assessment

The containers run without `privileged`, host networking, or Docker socket
access, and use `no-new-privileges`; only the web port is published, and only on
`127.0.0.1`. PostgreSQL and Valkey are reachable only inside the Compose
network.

The administrator and database passwords are set in `.env` and end up in the
container environment: keep the file at mode `600`, out of Git, and replace the
example values before the first start. After installation, enable two-factor
authentication — Nextcloud holds the files, calendars, and contacts of several
people at once.

The app store deserves particular care: add-ons execute code on the server with
Nextcloud's privileges, so install only the ones you trust. The built-in
"Security & setup warnings" page shows what your particular installation is
missing; after publishing over HTTPS it is worth walking the list and closing
the warnings.

The main image is scanned with Trivy; the critical CVEs it found are listed on
the card — mostly issues in the Debian system libraries the image is built on,
which upstream closes with the next release. PostgreSQL and Valkey are pinned
separately from the Nextcloud version and are outside the automated check.
