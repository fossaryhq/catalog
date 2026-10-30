# Netdata troubleshooting

<!-- coverage:troubleshooting -->
Start with `docker compose ps` and `docker compose logs --tail 100 netdata gateway`. Use the actual project directory and `.env` consistently. Do not paste credentials, API keys or full archives into issues.

## Gateway refuses to start

Replace the placeholder with a bcrypt hash from `caddy hash-password`. Keep single quotes around the hash in `.env`, because its dollar signs must not be interpolated. Ensure `config/Caddyfile` is readable (mode 644). The official Caddy binary carries a file capability; this recipe retains `NET_BIND_SERVICE` even though it listens on 8080. Removing it can make binary execution fail with “Operation not permitted”.

## 401, including through HTTPS

Use the username from `.env` and the original password, not its hash. The gateway password can be rotated by replacing the hash and recreating `gateway`. An outer proxy must preserve Authorization; do not solve 401 by bypassing the gateway or publishing the Agent port.

## No published port

The gateway needs its frontend bridge network as well as the Agent's private network. An internal-only network does not publish a usable host port on some Docker versions. Keep both gateway networks; the Agent stays on the private one.

## Dashboard loads slowly or never becomes network-idle

The UI uses live requests and may contact Netdata domains. Wait for visible charts, not network-idle. Open `/v3/` directly for the bundled interface. Browser resource loading and Agent telemetry are separate. A Cloud sign-in button does not mean local collection requires a Cloud account. The modern UI's Live function tables do require a claimed Agent and Cloud sign-in.

## Missing process, device or container metrics

Read [the official collector privilege matrix](https://github.com/netdata/netdata/blob/v2.12.2/packaging/docker/README.md). This recipe does not grant extra SYS_ADMIN/SYS_PTRACE, unconfined profiles, host networking or a Docker socket. Permission warnings for some process descriptors are expected. Under Docker Desktop, the Linux VM is monitored. Some newly mounted host filesystems appear only after restarting the Agent. Do not assume all physical hardware or per-container labels were verified.

## Host information is wrong

Check `NETDATA_HOSTNAME` and authenticated `/api/v1/info`. Compare CPU count with the mounted host `/proc`, not container resource limits alone. The host root, `/proc`, `/sys` and OS-release mounts must refer to the same Docker host. Remote Docker daemons resolve bind paths on the daemon machine, not your client laptop.

## Restore rejected or history missing

Keep the original archive unchanged. Restore requires both volume archives and the configuration reference. Absolute paths, traversal and links in the metric archives are rejected. A failed validation must leave the running installation untouched. Check disk space and use matching pinned image versions; restoring only `/var/lib/netdata` loses dbengine history in `/var/cache/netdata`.

## Security scan findings

The recorded scan found eight CRITICAL package findings across the pinned Agent and gateway images. Some are repeat CVEs across packages. Track upstream fixes and rescan reviewed images; do not treat startup or restore success as proof the findings are fixed.
