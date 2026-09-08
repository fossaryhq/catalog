# The mandatory application page

This document defines the minimum publication contract. The requirements apply
to every application and to every supported locale. An incomplete page must not
pass catalog validation, and must not be published.

## Page contents

Every application needs:

- a clear short and long description in English and in every supported locale;
- what it is for, who it suits, and the cloud services it replaces;
- a local `.svg` logo (square viewBox, mark only, no editor leftovers) and up to
  five local `.webp` screenshots from different screens and in different themes,
  each with a translated `alt`; three to five is the standard a page is written
  towards, and the floor is lifted only until the MVP catalog is filled;
- the languages the application is implemented in, spelled as GitHub Linguist does;
- the application licence, its kind, its restrictions, and a separate recipe licence;
- minimum CPU, RAM, and disk, recommended RAM, GPU, the datastore the recipe
  runs, and dependencies;
- how the application authenticates people: OIDC, SAML, two-factor
  authentication, and reverse-proxy header login;
- installation and maintenance difficulty on a 1-5 scale, and what a version
  upgrade costs;
- readiness of the `home`, `vps`, and `reliable` installation levels, each
  `supported`, `partial`, or `unsupported`;
- project status, the date of the last release, and when upstream metadata was checked;
- GitHub Stars or an equivalent figure, together with the exact time it was read;
- the number of upstream releases in the last year and when they were counted;
- the supported architectures and a separate smoke-test result for each;
- web, Android, iOS, and desktop clients, including an explicit "no client";
- the date the page was last updated;
- an editorial security assessment, its date, and the known risks;
- separate snapshots of the checks for new releases, critical vulnerabilities,
  breaking updates, upstream Compose, and outdated Docker images;
- unique localized SEO metadata and a preview for search engines and social networks.

`classification.implementation_languages` lists the languages the application
itself is written in and drives a catalog filter. Include a language at 5% of the
code or more according to GitHub Linguist, and leave out markup, template, and
build languages: HTML, CSS, SCSS, Vue, Svelte, Handlebars, Dockerfile, Makefile,
Shell, and the like. Take the spelling from Linguist (`Go`, `JavaScript`, `C#`).
A new spelling is reviewed deliberately, because otherwise `Golang` and `Go`
become two separate filter options. The languages are locale-neutral and are
never duplicated in a translation file.

The star count is a snapshot of mutable upstream data. It must not be stored
without `stars_checked_at`, and must not be presented as a live figure. The same
holds for `upstream.releases_last_year`: it is a count taken from the release
feed, not an editorial impression of how active a project feels, so it needs
`releases_checked_at`, and it cannot claim releases the `last_release_at` date
contradicts.

`auth` answers one question per mechanism, and answers it about the free
self-hosted build this recipe deploys: `native` when the mechanism ships with it,
`plugin` when an official or community add-on has to be installed, `paid` when it
is sold with a licence tier, `none` when it does not exist. `auth.proxy_header`
is separate: it says the application itself trusts a user name from an
authenticating reverse proxy, which is how single sign-on reaches an application
that speaks no protocol of its own. Fronting any application with a proxy is not
enough — the application has to read the header.

`requirements.database` is the datastore the recipe actually runs, not the ones
the application supports: `postgresql`, `mysql`, `mariadb`, and `mongodb` are
cross-checked against the images in `compose.yaml`, `sqlite` and `none` describe
what stays inside the application container, and `other` covers an embedded store
of another kind, such as the H2 file Stirling PDF keeps. `requirements.dependencies`
stays the human-readable list of everything else the stack brings up.

`operations.update_complexity` describes the documented upgrade of this recipe
and must match its `installation.md`: `in_place` when changing the tag and
restarting is the whole procedure, `manual_steps` when the update section
mandates commands or an order of component updates, and `staged_migration` when
major versions cannot be skipped or the data has to be migrated.

The `home` level means a minimal setup for a local network or a VPN. The `vps`
level adds a domain, HTTPS, and off-server backups. The `reliable` level requires
a separate database, healthchecks, monitoring, and resource limits. The status
judges the published recipe, not what the upstream application could theoretically
do; a component the recipe does not ship must never be marked `supported`.

Every signal in `update_tracking` carries its own status and `checked_at`. A
known positive or negative result without a check date is forbidden. `unknown`
means the check has not run, and `not_tracked` for Compose means the recipe has
no upstream Compose to track. A Trivy configuration scan is not a Docker image
vulnerability scan. The site presents these values as a stored snapshot and must
never call them live data.

The sources for the automated checks are declared separately in `update_policy`.
The registry, the image repository, and the upstream Compose baseline must not be
guessed from the Compose file. `provider: docker_hub` and `provider: ghcr` are
supported. Only Docker Hub serves a tag listing, so ghcr images take part in the
image scan but not in the outdated-tag check, and `outdated_images` stays
`unknown` for them. The Docker Hub tag spelling is not guessed from the version:
the check first tries the conventional form without a `v` prefix and then the one
that repeats the release tag verbatim, as `adguard/adguardhome:v0.107.79` does.
The tag it finds is also the tag the scanner uses. An empty
`update_policy.images` means there is nothing to scan: the result of such a check
is `unknown`, not `no_findings`.

Only images whose tag equals `recipe.application_version` belong in the policy:
the check looks for exactly that version in every listed repository. Sidecars
such as `postgres`, `valkey`, or `meilisearch` are versioned independently, so
listing them is forbidden — the tag is not found, the check reports an error, and
it exits with code `4`. When an application has no trackable image at all (its
official image is published outside Docker Hub and ghcr, say), the policy stays
empty with a comment explaining why.

Fossary's integration pipeline runs a read-only update check; the snapshot in
the manifest may only be updated after the result has been reviewed. Trivy is
used for the full image check when it is available.

The daily workflow stores the JSON as an artifact and renders the findings into
the run summary, but it stays green on exit `1` and fails only on anything
above it. A finding is something to review, not a broken pipeline: published
images almost always carry a base-image CVE, so failing on findings would paint
the job red every day, and a job that is always red stops being read. A red run
therefore means a check could not complete.

`upstream.release_source: manual` turns the release check off for an application
whose feed cannot be read automatically, and the site keeps showing the
hand-reviewed snapshot from the manifest. Two cases in this catalog: n8n
publishes several maintained lines as full releases, so `/releases/latest`
returns whichever shipped last rather than the line the recipe tracks; PhotoPrism
tags releases by date with a commit suffix (`260728-bbde8f452`), which no SemVer
comparison can order. Reach for it only when the feed is genuinely unreadable —
not to silence a finding that deserves an answer.

## Recipe files

An application directory must contain:

```text
manifest.yaml             English editorial fields
compose.yaml
.env.example
LICENSE
description.md            English
installation.md           English
troubleshooting.md        English
i18n/<locale>.yaml        translated editorial fields
i18n/<locale>/assets/<screenshot>.webp   # optional, overrides the source capture
i18n/<locale>/description.md
i18n/<locale>/installation.md
i18n/<locale>/troubleshooting.md
smoke-test.sh
proxy/Caddyfile
proxy/nginx.conf
proxy/traefik.yaml
assets/<logo>.svg
assets/<screenshot>.webp  # up to 5, none required while the catalog fills up
```

The integration validator defines the set of required locales and asks for
those files and no others. The current source locale is English and the
required translation locale is Russian (`ru`).

Additional `backup.sh` and `restore.sh` files are mandatory whenever the
procedure cannot be carried out safely and unambiguously with the commands in the
guide.

## The guide

The English guide and every translation must cover equivalent sections:

- installation on the supported Ubuntu and Debian versions;
- running on a VPS;
- access from a trusted local network;
- domain and HTTPS;
- Caddy, Nginx, and Traefik examples;
- where the data lives, and what every `.env.example` variable does;
- backup, and keeping a copy off the server;
- restore, with a warning that it replaces data;
- update, with a pinned image version;
- a step-by-step rollback, database migrations included;
- stopping while keeping the data, and removing everything;
- common errors and the commands to diagnose them;
- links to official sources for any claim about data or security.

Stable `coverage:*` HTML markers let the integration validator check that the
sections are all present, whatever language the headings are in. Copy the
markers from an existing published application and keep their names unchanged.

## Localization

Every published application must ship a translation for each locale in
`catalog.TranslationLocales`. The translated fields are the tagline, the summary,
the categories, the complete Markdown documents, the licence notes, the security
risks, the smoke-test limitations, and the `alt` of every screenshot. Technical
identifiers, SPDX expressions, image names, and brands are not translated.

A missing translation is a build error. Falling back to English under a
translated URL does not count as localization.

Screenshots are localized too. A screen is declared once in
`content.screenshots`, and each locale supplies its own capture under the same
file name: `i18n/<locale>/assets/<name>.webp` when the locale has one, and
`assets/<name>.webp` otherwise. A screen captured in neither is dropped for that
locale, and a page left with none renders the gallery's empty state — a reader
is better served by "no screenshots yet" than by an interface in a language they
do not read.

So a declared screenshot does not have to exist at the source path, but it must
exist somewhere: a declaration no locale supplies is rejected, and so is an
override whose file name matches no declaration. `catalogctl report` lists the
locales still short of the full set.

## SEO

Every application must be SEO-ready in every locale. There are no separate
duplicate SEO fields: the page title is composed from `name` and the localized
`tagline`, and the `meta description` from the localized `summary`. So `tagline`
has to describe briefly what the application is for, and `summary` has to stand on
its own in 40 to 600 characters. The brand in `name` is not translated; identical
or empty translations are forbidden.

A published page must carry a canonical URL, mutual `hreflang` links for every
locale, Open Graph and Twitter Card metadata with a local screenshot, and JSON-LD
`SoftwareApplication` and `BreadcrumbList`. The page must appear in `sitemap.xml`,
and indexing must not depend on JavaScript.

## Compose validation

Every tracked `compose.yaml` passes two different levels of checking:

1. Public CI validates interpolation and the Compose model with
   `docker compose config` and the application's `.env.example`.
2. Fossary's integration pipeline runs the application's mandatory
   `smoke-test.sh` in an isolated environment.

A full smoke test must `pull`, start the original Compose file, wait for the
healthcheck, make an application-level HTTP/API request, print the logs, and
remove the containers, networks, and volumes even on failure. The workflow runs
for changes and pushes to `main` — only for the recipes the diff touched, one
matrix job per application — and the whole catalog is checked weekly and on
demand. It does not look at `publication_status`: a draft's `smoke-test.sh` has
to pass exactly like a published one.

A local caveat: on Docker Desktop for Windows some high ports are reserved by
Hyper-V (`netsh int ipv4 show excludedportrange`), so recipes that publish random
high ports — Syncthing, for instance — fail with `ports are not available …
forbidden by its access permissions`. A free port is requested from the kernel
inside WSL2 but published on the Windows host, where the reservation may already
hold it. On a Linux runner in CI it is the same kernel, so the check passes there;
a local failure with that message is not a defect in the recipe.

The check in `healthcheck` and the check in the smoke test are matched against
what the application actually answers. An exact pattern such as `"status":"pass"`
will not match pretty-printed JSON with a space after the colon: the container
stays `unhealthy`, `docker compose up --wait` fails, and the recipe looks broken
while the application is perfectly healthy.

An architecture's status becomes `passed` only after a successful run on that
architecture. A multi-arch image does not prove that ARM64 works. `smoke_test:
full` means a full smoke on at least one explicitly named architecture, and the
test's limitations are always shown to the reader.

Every `full` or `partial` recipe also keeps `recipe.check_history`, newest first.
The first entry must reproduce the current `tested_at`, `application_version`,
recipe version, architecture results, smoke level, and restore result. Older
entries remain attached to the versions they actually tested. A history entry
represents a performed check, so it cannot contain only `not_tested`
architectures; a recipe whose current status is `not_tested` may omit history.
Historical architecture failures stay in the record, while the localized
`smoke_test_limitations` describe the latest check.

A check does not last forever, and it can also fail or be overtaken. All three
states are derived, never stored:

- `stale` from `recipe.tested_at`: a recipe goes stale after 90 days, or after 30
  when the upstream regularly ships breaking changes, which is declared with
  `recipe.recheck_interval_days: 30`. The field accepts only 30 or 90 and may be
  absent; absent means the standard window. The short window is set on evidence,
  not on a hunch — the breaking changes are described in `description.md`, as
  they are for Immich.
- `broken` when the current check failed on every architecture it covered and
  passed on none. A single passing architecture is a limitation of the check, not
  a broken recipe, and belongs in `smoke_test_limitations`.
- `review_required` when upstream has published a major version above
  `recipe.application_version`. This compares version numbers; it says a review
  is due, never that the update breaks. The verdict that an update is compatible
  or incompatible is a manual `update_tracking.breaking_updates` value, entered
  after reading the release notes and the migration steps.

More than one can apply at once, and each of them shows in the page badge, the
catalog filter, the column on `/status`, and the daily `catalogctl state`
report. None of them lowers the smoke-test level: they are shown beside it.

## The publication criterion

`publication_status: published` makes a page public. `publication_status: draft`
keeps the page out of every public route, counter, sitemap, search index, and
downloadable bundle while it is still being worked on; it validates exactly like
a published page, so promoting one is a single field change.

Screenshots are the one part of the contract that is relaxed for the MVP. A
published page may ship none: capturing a set means running the application by
hand with realistic content, and that queue was holding finished recipes back.
The page says plainly that screenshots are missing, `catalogctl report` lists who
is short of a full set, and the three-shot minimum returns before the public
launch; this is a temporary publication exception, not a rule that was dropped.

Before publication an application must pass the public checks:

```bash
pipx run check-jsonschema==0.33.3 \
  --schemafile schemas/app-manifest.schema.json \
  apps/*/manifest.yaml

docker compose \
  --env-file apps/<slug>/.env.example \
  --file apps/<slug>/compose.yaml \
  config --quiet
```

Fossary additionally runs semantic catalog validation, smoke tests, generated
configuration tests, and website integration tests before deploying a catalog
revision.

The smoke test may be skipped only for a draft whose status visibly reads
`not_tested`; such a recipe must never be called verified or ready to run.
