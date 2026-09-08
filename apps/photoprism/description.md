PhotoPrism turns a directory of photos and videos into a private web library. It
indexes the existing folder structure, reads EXIF and XMP, generates previews,
shows calendar and map views, recognizes faces, and searches with filters. It is
suited to personal or family archives as an alternative to Google Photos,
iCloud Photos, and cloud file viewers. Community Edition has no first-party
native mobile app for automatic uploads.

The recipe runs official PhotoPrism image `260728`, corresponding to release
`260728-bbde8f452`, with MariaDB 12.3.2. Originals and writable storage use host
directories, while the database uses a separate Docker volume. Optional Ollama,
PhotoPrism Vision, Watchtower, and hardware acceleration are deliberately absent.

<!-- coverage:security-assessment -->

### Security and recipe boundaries

The full HTTP smoke test has passed on amd64 and arm64; backup, restore, and real
media processing remain untested. The port binds to localhost, MariaDB is not published, and
password authentication is required. The recipe does not encrypt originals,
previews, the database, or `.env`. The indexer passes untrusted formats to
external libraries and needs bursts of memory while it works. The recipe
therefore sets no memory limit — a tight cap gets the indexer OOM-killed
mid-run — so size the host for the peak instead.

Community Edition is available under AGPL-3.0, while additional upstream terms
protect the trademark and brand assets. Some paid-edition capabilities are not
part of Community Edition; consult upstream's current comparison.
