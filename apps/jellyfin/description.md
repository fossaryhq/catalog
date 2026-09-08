Jellyfin is a media server for a home collection of movies, series, music, and
photos. It scans your folders, fetches artwork, descriptions, and cast lists,
remembers where you stopped, and streams video to the browser, a phone, a
tablet, a TV, and a set-top box. It suits anyone who keeps a library locally and
does not want to depend on subscriptions or on a service staying available.

The project is a fork of Emby made after it moved to a closed license, and it
stays entirely free software: no paid features, no subscription, no vendor
account. Clients exist for Android, iOS, Android TV, Kodi, and desktop systems,
and the web interface works in any browser.

The recipe runs a single container. Settings, the database, and metadata live in
a Docker volume, the cache in a second volume, and the media directory is mounted
read-only. The `reliable` level is not claimed: Jellyfin uses embedded SQLite,
and the recipe adds no monitoring and no resource limits.

> Transcoding is the heaviest thing the server does. If clients play files
> directly, a weak CPU is enough; if they cannot, you need a fast CPU or hardware
> acceleration, which this recipe does not configure.

<!-- coverage:security-assessment -->

### Security assessment

The container runs without `privileged`, host networking, or Docker socket
access, and uses `no-new-privileges`; only the web port is published, and only on
`127.0.0.1`. The media library is mounted read-only, so the server cannot modify
or delete your files. DLNA and autodiscovery, which need host networking, are
deliberately disabled.

The main risk is the first start: the setup wizard requires no password, and the
port must not be exposed until the administrator account exists. The container
runs as root, as in the upstream instructions; if that matters, set `user:` and
adjust volume ownership yourself. Publish the server over HTTPS only, enforce
strong passwords, and keep the number of external users small: a single 4K
transcode can saturate the CPU.

The recipe image is scanned with Trivy; the critical CVEs it found are listed
on the card. As with any large media server, these are mostly base image system
library issues that upstream closes with the next release.
