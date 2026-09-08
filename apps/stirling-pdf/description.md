Stirling PDF is a web suite of more than 60 PDF operations: merging and
splitting, editing, OCR, office-format conversion, compression, signing,
metadata editing, and automation pipelines. It suits personal or small internal
document workflows that would otherwise send files to Adobe Acrobat Online,
Smallpdf, or iLovePDF. An official desktop client can connect to a self-hosted
server.

The recipe runs the pinned 2.14.3 standard image with mandatory authentication
and embedded H2, and the interface defaults to English — one variable switches
it. Settings, users, and H2 persist in `/configs`; branding lives under `/customFiles`, automation under `/pipeline`,
and OCR data under `/usr/share/tessdata`. External PostgreSQL is omitted because
upstream classifies custom databases as paid Server/Enterprise functionality.

<!-- coverage:security-assessment -->

### Security and licensing

The full application smoke test has passed on amd64; backup and restore remain
untested in practice. Authentication is enabled, while URL-to-PDF,
analytics, PostHog, Scarf, and search-engine indexing are disabled. Complex PDF
and office files remain untrusted input that can attack parsers or exhaust
resources.

Stirling PDF is open-core, not wholly MIT. The standard image contains parts
under the Stirling PDF User License, which restricts production, commercial,
and client-facing use without a subscription. Upstream also advertises a Free
tier for up to five users; because the interaction is unclear, obtain written
confirmation of applicable rights before production use.
