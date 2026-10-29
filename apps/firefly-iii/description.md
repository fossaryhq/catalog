# Firefly III

Firefly III is a personal finance ledger for people who want to keep account balances, income, expenses, transfers, budgets, subscriptions and savings goals on their own server. Attach a receipt to a transaction, categorize spending, and inspect how money moved through your accounts. It can replace the record-keeping part of Quicken or Monarch Money; it does not reproduce their managed bank connections.

Compared with an envelope-first tool such as Actual Budget, Firefly III centers on accounts and transactions, with budgets and rules built around that ledger. It is useful for detailed historical spending and multiple accounts. Choose an envelope tool when assigning every available unit of money is the primary workflow.

The recipe runs Firefly III 6.7.9, PostgreSQL 18.6 and an Alpine 3.22.2 cron service. Scheduled jobs run daily at **03:00 UTC**, including recurring transactions and automatic budgets. The separate Data Importer and external bank services are not installed. SMTP is also unconfigured: mail is written to the protected application log.

The browser is the primary client. Android and iOS clients are third-party projects, including Waterfly III and Abacus, listed in the [official integration directory](https://docs.firefly-iii.org/references/firefly-iii/third-parties/apps/); no desktop client is included, and those mobile apps were not tested. English and Russian are available in the interface. The application and its logo use AGPL-3.0-or-later, while these deployment files use MIT; the logo notice is in `assets/NOTICE`.

Local email/password login and native TOTP are available. TOTP must be enabled in the profile and recovery codes stored safely. There is no native OIDC or SAML integration. An optional remote-user header guard exists upstream, but this recipe keeps password login: the header guard performs no identity checks of its own.

The default single-user mode closes public registration after the owner registers. Before that, whoever reaches the installation first can become its owner. Complete registration over loopback or an SSH tunnel before opening the proxy or LAN access.

<!-- coverage:security-assessment -->
Financial records live in PostgreSQL; attachments and the OAuth signing keys have their own persistent storage. The recipe deliberately preserves the whole Laravel storage directory as well as the separate upload volume, so recreating a container or restoring an archive does not invalidate API tokens by losing their signing keys. Treat all three volumes and `.env` as sensitive. Backup archives include unencrypted financial records and the keys needed to read encrypted attachments.

The amd64 smoke test exercises registration, login, a personal API token, an account, an expense, its category and tag, a real attachment, the cron endpoint and recovery after deleting every volume. arm64, overnight scheduling, TOTP, mail, bank integrations and mobile clients remain untested. Eight CRITICAL package findings across the pinned images are retained in the security snapshot. This functional check is not a security certification.

The home and VPS levels are supported after safe owner bootstrap. The reliable level is partial: PostgreSQL and healthchecks are present, but resource limits, external monitoring and backup scheduling still need an operator. Size the server with at least 1 CPU, 1 GiB RAM and 5 GiB disk; 2 GiB RAM gives more room for PHP and PostgreSQL. Large attachments and history need more storage.

Official references: [Docker installation](https://docs.firefly-iii.org/how-to/firefly-iii/installation/docker/), [backups](https://docs.firefly-iii.org/how-to/firefly-iii/advanced/backup/), [authentication](https://docs.firefly-iii.org/how-to/firefly-iii/advanced/authentication/), [cron](https://docs.firefly-iii.org/how-to/firefly-iii/advanced/cron/), and [6.7.9 release notes](https://github.com/firefly-iii/firefly-iii/releases/tag/v6.7.9).
