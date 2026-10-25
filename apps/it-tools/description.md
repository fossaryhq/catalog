# IT Tools

A private browser toolbox for development: Unicode encoding, hashes, data formats and other small operations. This recipe serves the official static build without a database or user accounts. The pinned version has no Russian interface; Russian screenshots show the native English UI with original Russian sample data.

Favorites, theme, language and some tool inputs live in browser storage. The server has no copy. Moving machines or clearing the site needs a separately retained browser profile if you want those preferences back.

The latest stable release is dated 2024-10-22; no newer stable release was found on 2026-10-25. The image is pinned; this does not promise current dependencies. Browser smoke verifies Unicode Base64 roundtrip, SHA-256, JSON-to-YAML and invalid JSON rejection without off-origin requests in those scenarios.

<!-- coverage:security-assessment -->
Configuration assessment (2026-10-25): loopback, UID 101, read-only root, no capabilities and no persistent application volume. Authentication is not built in. Image vulnerabilities were not scanned. Avoid production secrets in a shared browser. VITE configuration is baked at build time and cannot be changed through runtime env.
