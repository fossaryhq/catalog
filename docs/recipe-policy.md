# Recipe policy

A recipe is published only when it meets the full contract in
[`app-requirements.md`](app-requirements.md).

## Mandatory rules

- Never use the `latest` tag.
- Never add the legacy `version` key to Compose.
- Do not publish databases or administrative ports without a reason.
- Bind the web port to `127.0.0.1` when a reverse proxy on the host is expected.
- Never keep passwords, tokens, or any other secret in Git.
- Document every parameter in `.env.example`.
- Document where user data lives.
- Describe backup, update, rollback, and removal separately.
- Explain the risk behind `privileged`, host networking, or a Docker socket mount.
- Never claim a full smoke test on the strength of a syntax check.
- Ship up to five local screenshots; none are required while the MVP catalog is
  being filled, and three to five remain the standard for launch. Localized
  descriptions and a star count with its check date are required either way.
- Include Caddy, Nginx, and Traefik examples.
- Verify every recipe with a mandatory `smoke-test.sh` on the CI schedule, drafts
  included: the smoke workflow does not look at `publication_status`.
- Check healthcheck and smoke-test templates against what the application
  actually answers, not against the JSON you expect it to answer.

## Statuses

- `full` — the application started, reached its healthcheck, and passed an
  application-level check.
- `partial` — Compose and a basic start are verified, but the scenario is not
  covered end to end.
- `not_tested` — the recipe is prepared, but an isolated run has not happened yet.

Security scan results are judged separately from whether the recipe works.
