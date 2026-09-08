Immich is a photo archive for your own server that reproduces the familiar cloud
gallery workflow: the Android and iOS apps upload photos and videos
automatically, and the web interface shows a timeline by date, albums, a map,
memories, and link sharing. It fits a family leaving Google Photos or iCloud, and
a photographer who needs an archive without storage tiers.

A separate machine learning container adds content-based search without manual
tags, face recognition, duplicate detection, and text recognition. All of it runs
on your server: the photos never leave it.

The recipe brings up four containers — the server, machine learning, PostgreSQL
14 with vector extensions, and Valkey. Originals, thumbnails, and transcodes live
in a host directory, the database in a Docker volume. The `reliable` level is
declared partial: the database is a separate service and every container has a
healthcheck, but the recipe sets no resource limits and adds no external
monitoring.

> Immich is under active development and still ships breaking changes regularly.
> Read the release notes and take a backup before every update.

<!-- coverage:security-assessment -->

### Security assessment

The containers run without `privileged`, host networking, or Docker socket
access, and use `no-new-privileges`; only the web port is published, and only on
`127.0.0.1`. PostgreSQL and Valkey are reachable only inside the Compose network.
Immich has no public sign-up: the administrator creates accounts.

A photo archive is sensitive data: geotags, faces, the shape of your daily life.
Expose Immich over HTTPS only, enable two-factor authentication, update the
images promptly, and encrypt copies that leave the server. The PostgreSQL
password sits in `.env` next to the recipe — keep the file at mode `600` and out
of Git. The recipe sets no CPU or memory limits, so on a small server machine
learning jobs can starve the other services; add `deploy.resources` or disable
machine learning if that matters.

The `immich-server` and `immich-machine-learning` images are scanned with
Trivy; the result and the CVE list are shown on the card. Valkey and PostgreSQL
are pinned by digest and their tags do not follow the application version, so
they are outside the automated check — update them together with the upstream
Compose file.
