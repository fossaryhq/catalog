# Contributing

Contributions that improve an existing entry or add a well-researched
self-hosted application are welcome.

## Opening an issue

Three forms cover what the catalog needs to hear: a catalog problem (wrong
data, a broken recipe, documentation, an asset), an application suggestion, and
an installation result.

An installation result is worth reporting when it went well, too. A recipe is
written and smoke-tested on a handful of machines, and a report from a
different server is the only evidence that its instructions hold anywhere else
— so "it worked, here is what I ran it on" is a useful issue. The application
page on [fossary.com](https://fossary.com) prefills the recipe context for you.

Security issues go through private vulnerability reporting instead, as
described in [SECURITY.md](SECURITY.md); do not put vulnerability details in a
public issue.

## Before opening a pull request

1. Read the [application requirements](docs/app-requirements.md),
   [recipe policy](docs/recipe-policy.md), and
   [editorial guide](docs/editorial-guide.md).
2. Use official documentation, repositories, releases, and container images as
   primary sources.
3. Never commit passwords, tokens, private keys, customer data, or other real
   credentials. Values in `.env.example` must be obvious placeholders.
4. Pin container images to a version. Do not use `latest`.
5. Write English source content first and keep every existing translation in
   sync.
6. Do not claim a smoke or restore result you did not perform.

## Local checks

Validate manifests with:

```bash
pipx run check-jsonschema==0.33.3 \
  --schemafile schemas/app-manifest.schema.json \
  apps/*/manifest.yaml
```

Validate a Compose recipe with its example environment:

```bash
docker compose \
  --env-file apps/<slug>/.env.example \
  --file apps/<slug>/compose.yaml \
  config --quiet
```

Run the recipe's smoke test only on an isolated machine where its containers,
volumes, and networks can be safely created and removed.

## Pull requests

Keep a pull request focused on one application or one catalog-wide contract
change. Explain the source of changed facts and list the checks you performed.
Screenshots must come from a real instance with realistic, non-sensitive data.

Catalog changes are integrated into the private Fossary application only after
the public checks and the full application integration suite pass.

By contributing, you agree that your changes are licensed under the license
that applies to the files you modify, as described in [LICENSE.md](LICENSE.md).
