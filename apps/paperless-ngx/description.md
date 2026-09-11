Paperless-ngx turns a folder of scans and PDFs into a searchable archive. It
keeps originals, creates PDF/A renditions and thumbnails, recognizes text,
extracts metadata, and automatically suggests tags, document types, and
correspondents. It suits personal, family, and small workplace archives and can
replace cloud document storage and manual folder searches.

This recipe runs the pinned Paperless-ngx 3.1.2 image with PostgreSQL 18 and
Valkey 9. English OCR is enabled by default, and one variable adds more
languages. Application data, originals and derived files, import/export, the
database, and broker state use separate Docker volumes. Tika and Gotenberg are omitted, so this recipe does not
support Office and email ingestion that requires those services.

<!-- coverage:security-assessment -->

### Security and recipe boundaries

The full smoke test has passed on amd64, and the document export and import
round trip runs inside it: a page is consumed, backed up, deleted, restored, and
checked for its recognized text. arm64 remains untested. Paperless-ngx does not encrypt documents or recognized text at rest;
sensitive archives need disk encryption and encrypted off-server backups. OCR,
Ghostscript, and image handlers process untrusted files that can exhaust
resources or attack parsers. The web port binds to localhost, while PostgreSQL
and Valkey are not published at all.
