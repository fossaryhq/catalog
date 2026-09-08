# Editorial standard

English is the source language. Every page is written in English first and then
translated; a translation never becomes the original.

## Tone of voice

**Smart. Practical. Calm.** Write the way a competent colleague explains
something they have actually run:

- technically accurate, and specific about what was and was not verified;
- friendly, never condescending;
- short — cut the sentence that only restates the previous one;
- plain, so a reader who is new to Docker still follows;
- free of marketing superlatives, and free of jargon used as a badge.

Prefer the concrete verb to the abstract noun. Instead of

> A comprehensive directory of self-hosted FOSS solutions.

write

> Find self-hosted apps and deploy them on your server.

Brand phrases from the brand guide (§16) — "Own your software", "Your apps. Your
data. Your server." — belong in marketing surfaces, not inside an application
page. A recipe page states facts.

## Sources

Use them in this order:

1. the official documentation;
2. the official repository and its release notes;
3. the official container image;
4. our own verification log;
5. the issue tracker;
6. third-party material, and only as a supporting reference.

## Page structure

The text must explain what the application is for, who it suits, its limits, the
system requirements, installation, publishing over HTTPS, backup, updates,
rollback, and troubleshooting.

Never copy or translate somebody else's page wholesale. A technical claim that
could affect a reader's data or security needs a link to an official source.

The complete required set of page, translation, and recipe files is defined in
[`app-requirements.md`](app-requirements.md). An editor may not drop a section
because the answer is negative: a missing mobile client, an untested restore, or
an extra licence restriction is stated explicitly.

## Translations

A translation carries the same facts and the same structure as the English
source. `screenshot_alts`, `security_known_risks`, and `smoke_test_limitations`
are compared element for element at build time, so a translation that drops or
merges an item fails the build rather than shipping a shorter page.

Locale-neutral values — `classification.alternatives_to`,
`classification.tags`, `classification.implementation_languages` — stay in
`manifest.yaml` and are never translated.
