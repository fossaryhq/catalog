Vikunja is a self-hosted task manager for household work and small team projects. Collect tasks in projects, switch between a list and a kanban board, set priorities and deadlines, and keep notes and attachments beside the work. Recurring tasks, labels, assignees, and project sharing support routines that need more than a personal checklist.

It can replace the task-list part of Todoist or a straightforward Trello board. It does not reproduce every hosted automation, integration, or enterprise administration feature. The interface includes English and Russian. Use the web interface on computers and phones, or the project's separately distributed desktop wrapper; this recipe does not provide a native Android or iOS client.

The recipe pins the **official Vikunja 2.7.1 image** and PostgreSQL 18.4. The app runs as UID/GID `1000:1000`, with a read-only root filesystem and a temporary `/tmp`; a short-lived Alpine container assigns ownership of its data volume. The app volume holds attachments under `/data/files`, while a separate PostgreSQL volume holds tasks, accounts, permissions, and settings. Neither the database nor an administrative port is published.

PostgreSQL is a deliberate choice: the SQLite trial of this release returned `database is locked` when deleting a task and moving it between board columns. This recipe's smoke test uses PostgreSQL and checks real task/attachment creation, deletion, and recovery. Resource figures are planning estimates for a small installation: one CPU core, 1 GB RAM minimum, 2 GB recommended, and 5 GB disk before attachments. Both service images offer amd64 and arm64; only amd64 has been run here. The reliable level is partial because monitoring, resource limits, and high availability are not included.

The server is AGPL-3.0-or-later licensed. Optional Pro features, including the web administration panel, require a separate license; the recipe uses the free core. Local accounts and native TOTP two-factor authentication are available, and OIDC can be configured separately. SAML and proxy user-header login are not supplied by this recipe. SMTP is not configured, so email reminders and email recovery need additional setup.

## Security assessment

<!-- coverage:security-assessment -->

Open registration is disabled, and there is no public default account: create the first user through the container CLI. Keep the service secret and database password private, expose the app through HTTPS, and protect both persistent volumes. Backups contain private tasks, attachments, and credentials; encrypt them and keep a copy off-server. Review share-link permissions before distributing links outside the registered user group. The functional checks do not constitute an image vulnerability scan.

Sources: [documentation](https://vikunja.io/docs/), [configuration](https://vikunja.io/docs/config-options/), [CLI](https://vikunja.io/docs/cli/), [backup/restore](https://vikunja.io/docs/backup-restore/), [official image](https://hub.docker.com/r/vikunja/vikunja), [desktop wrapper](https://github.com/go-vikunja/vikunja/tree/v2.7.1/desktop), and [release v2.7.1](https://github.com/go-vikunja/vikunja/releases/tag/v2.7.1).
