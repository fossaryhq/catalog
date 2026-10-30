# Netdata

Netdata collects Linux host metrics and shows live charts for CPU, memory, disks and network traffic. It stores metric history locally and evaluates built-in alerts. It suits a home server or a VPS where you want more detail than a simple uptime check. Compare it with Beszel for a lighter hub-and-agent approach.

This recipe runs the official 2.12.2 Agent and a mandatory Caddy password gateway. You do not need a Netdata Cloud account. Only the gateway is published, on loopback; the Agent API remains on a private Docker network. Collection and historical data work without claiming the Agent in Cloud.

## What is included

- Native host CPU, RAM, disk and network collection through read-only host mounts.
- Local dbengine history, SQLite metadata, Agent identity and management keys in persistent volumes.
- Password protection of the local UI and APIs, healthchecks, backup and tested recovery.
- The bundled modern web interface. Its license differs from the Agent's license.

## Limits

The Agent is GPLv3+, but the modern UI is closed-source under NCUL1. The complete deployment is therefore classified as proprietary in this catalog. NCUL1 permits use with Netdata components and restricts modification and reverse engineering. See the [upstream license explanation](https://github.com/netdata/netdata/tree/v2.12.2#scroll-license) and [NCUL1](https://app.netdata.cloud/LICENSE.txt).

The Agent has no local OIDC, SAML or MFA setup here; the gateway supplies HTTP Basic authentication. Cloud login, Cloud SSO, shared saved dashboards, streaming children and external notification services are outside this recipe. The modern UI's Live function tables require a claimed Agent and Cloud sign-in. There are no bundled native mobile or desktop clients. The tested UI and official documentation are English.

The monitored system is the Linux Docker host. On Docker Desktop that means its Linux VM. This is not complete Windows/macOS or physical-device monitoring. No Docker socket, extra SYS_ADMIN/SYS_PTRACE capabilities or unconfined profile is granted; some per-process and privileged collectors cannot read everything. Filesystems mounted after startup may require an Agent restart. See the [official container privilege matrix](https://github.com/netdata/netdata/blob/v2.12.2/packaging/docker/README.md).

Allow 512 MiB RAM at minimum, preferably 1 GiB, one CPU core and at least 5 GiB disk for a small single-host installation. Actual memory and retention depend on metric cardinality and collector load; these are planning estimates, not a hardware certification. See [Agent sizing](https://github.com/netdata/netdata/tree/v2.12.2/docs/netdata-agent/sizing-netdata-agents).

<!-- coverage:security-assessment -->
## Data and privacy

The Agent runs unclaimed, opts out of Agent telemetry with `DO_NOT_TRACK=1`, and has no outbound route on its internal network. The browser UI can load resources from or contact Netdata domains, including a registry iframe carrying the Agent identifier and hostname. Do not interpret the Agent's opt-out as a promise of no browser-side third-party traffic. See [telemetry controls](https://github.com/netdata/netdata/blob/v2.12.2/docs/netdata-agent/configuration/anonymous-telemetry-events.md).

The Agent reads the host root, `/proc`, `/sys`, OS information and account names, and shares the host PID namespace. Its entrypoint starts as root and launches the Agent as UID/GID 201. Read-only does not mean non-sensitive: protect the image, local access, archives and API keys. Eight CRITICAL package findings were recorded across the two pinned images; the successful functional test does not resolve them.

## Verification

On amd64, the complete recipe recorded real CPU/RAM charts and fixed historical CPU samples, then removed both data volumes. Recovery restored the original Agent identity, API-key hash and exact historical measurements. Anonymous UI/API requests were rejected; invalid archives, backup permissions, archive integrity, a safety backup and stopped-state backup were checked. ARM64, privileged collectors, Cloud integrations and notification delivery were not tested.
