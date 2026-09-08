Syncthing synchronises folders between your devices directly. A laptop, a phone,
and a server negotiate among themselves: files travel over an encrypted channel
from device to device, and there is simply no intermediate service holding a
copy. It fits anyone who wants the familiar "the same folder on every device"
without handing the contents to someone else's cloud.

The server in this recipe is not storage in the cloud sense but an
always-running participant in the exchange. A phone and a laptop are often off
and rarely see each other; a node on the server is always reachable, so changes
propagate faster and devices never have to be online at the same time.

The recipe runs a single container. The configuration, device keys, and index
database live in a Docker volume, and the synchronised files in a host
directory. The `reliable` level is not claimed: Syncthing has no separate
database, and the recipe adds no monitoring and no resource limits.

> Syncthing is not a backup. A deletion propagates to every device as fast as any
> other change. Enable File Versioning for folders where accidental deletion
> matters, and keep separate backups.

<!-- coverage:security-assessment -->

### Security assessment

The container runs without `privileged`, host networking, or Docker socket
access, uses `no-new-privileges`, and runs as the unprivileged user `1000:1000`.
Traffic between nodes is TLS encrypted, and devices identify each other by
cryptographic identifiers that must be confirmed by hand on both sides.

Syncthing's network model differs from the other apps in this catalogue: sync
port 22000 is published on all interfaces, because without it direct connections
never form and the exchange falls back to public relays. The web interface still
stays on `127.0.0.1` and is published only through a reverse proxy. It has no
password by default — set one before opening any access from outside.

The configuration archive contains the device's private key: anyone who obtains
it can impersonate your node inside the cluster. Encrypt the copies that leave
the server.

The recipe image is scanned with Trivy and has no critical findings — it is
Alpine plus a single statically linked Go binary.
