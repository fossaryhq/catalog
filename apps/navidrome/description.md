Navidrome is a music server for a collection that lives as files. It reads tags
and artwork, builds a library by artist and album, remembers ratings, playlists,
and listening history, and streams to a browser or a phone. It fits anyone who
spent years collecting music and would rather not watch tracks vanish from a
subscription catalogue.

The key feature is the Subsonic API: the project ships no mobile apps of its own,
but there are dozens of compatible clients, from Symfonium and substreamer on
Android to play:Sub on iOS and Feishin on the desktop. The server is written in
Go, fits in a single container, and runs on hardware as small as a Raspberry Pi.

The recipe mounts the music directory read-only and keeps the database, artwork,
and history in a separate Docker volume. The `reliable` level is not claimed:
Navidrome uses embedded SQLite, and the recipe adds no monitoring and no
resource limits.

> Anonymous usage statistics are disabled in this recipe
> (`NAVIDROME_INSIGHTS=false`). One variable turns them back on if you want to
> support the project with data.

<!-- coverage:security-assessment -->

### Security assessment

The container runs without `privileged`, host networking, or Docker socket
access, and uses `no-new-privileges`; only the web port is published, and only on
`127.0.0.1`. The music library is mounted read-only, so the server cannot modify
or delete your files.

The main risk is the first start: until the administrator account exists, the
setup form is open to whoever reaches it, so the port must stay unexposed until
you have created it. The second is the
protocol itself: the Subsonic API sends credentials with every request, and some
clients still send the password in clear text, so the server may only be
published over HTTPS. The container runs as root, as in the upstream image; if
that matters, set `user:` and adjust volume ownership yourself.

The recipe image is scanned with Trivy and has no critical findings. That is
what you would expect from an image made of Alpine plus a single statically
linked Go binary.
