# Fossary catalog

The public data source for [Fossary](https://fossary.com): a catalog of
self-hosted and open-source applications with reviewed Docker Compose recipes.

Each application lives under `apps/<slug>` and contains:

```text
<slug>/
├── manifest.yaml
├── compose.yaml
├── .env.example
├── LICENSE
├── description.md
├── installation.md
├── troubleshooting.md
├── smoke-test.sh
├── backup.sh
├── restore.sh
├── proxy/
│   ├── Caddyfile
│   ├── nginx.conf
│   └── traefik.yaml
├── assets/
│   └── logo.svg
└── i18n/
    ├── <locale>.yaml
    └── <locale>/
        ├── description.md
        ├── installation.md
        ├── troubleshooting.md
        └── assets/
            └── <localized-screenshot>.webp
```

English is the source language. Translations and localized screenshots live
under `i18n/<locale>`.

`publication_status` controls whether an entry is published on the website. A
`draft` remains visible in this repository and passes the same catalog checks,
but is omitted from production pages, search, sitemap, feeds, and downloadable
bundles.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md), the
[application requirements](docs/app-requirements.md), and the
[recipe policy](docs/recipe-policy.md) before submitting a change.

The public checks validate the JSON Schema, Compose files, shell syntax,
secrets, and security-sensitive configuration. Fossary also runs integration
checks before a catalog revision reaches the website.

## Licensing

The repository contains material under more than one license. See
[LICENSE.md](LICENSE.md) and [ASSETS.md](ASSETS.md) for the exact boundaries.
