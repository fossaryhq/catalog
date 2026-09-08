Actual Budget is envelope budgeting that runs entirely on your own machines.
Every client — the browser, the desktop app, a phone opening the same address —
keeps a full local copy of the budget and works offline; the server this recipe
runs is a sync endpoint that merges those copies and stores the file. Money is
assigned to categories for the month ahead, transactions are imported from
files or through bank integrations you configure yourself, and reports and
schedules are computed on the client.

This recipe runs pinned Actual 26.9.0 as a single container with SQLite in one
volume: `server-files` for the account database and `user-files` for the budget
blobs. The web port binds to localhost, and only password login is enabled —
the header and OpenID methods stay closed until an operator turns them on.

<!-- coverage:security-assessment -->

### Security and recipe boundaries

The full application smoke test has passed on amd64 and arm64, and practical
backup and restore have passed on amd64.
The server password is set in the browser on the first visit, so the recipe
holds no secret of its own — which also means the first person to reach an
unprotected instance owns it. Put HTTPS in front of it before the first visit
and do not expose the port directly. Actual's default configuration accepts
password, header, and OpenID logins at once; the recipe narrows
`ACTUAL_ALLOWED_LOGIN_METHODS` to `password`, because a trusted-header login
behind a proxy that does not strip the header is an open door. End-to-end
encryption is a per-budget setting inside the application: without it, budget
files sit on the server unencrypted and land unencrypted in every backup.
