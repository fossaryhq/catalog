### Devices cannot find each other

Check that the sync port is open from outside and that the node listens on it:

```bash
docker compose ps
curl --fail --silent http://127.0.0.1:8384/rest/noauth/health
sudo ufw status | grep 22000
```

In the web interface the Listeners row should show every address as active. If
the connection still goes through a relay, the device card shows Connection Type
`Relay` instead of `TCP LAN` or `TCP WAN` — the direct connection failed and
port 22000 is closed on at least one side.

### Permission error on the folder

The container runs as `1000:1000`, and a host directory often belongs to root:

```bash
ls -ld /srv/syncthing
sudo chown -R 1000:1000 /srv/syncthing
```

`SYNCTHING_UID` and `SYNCTHING_GID` set a different owner when the server needs
one.

### A file was deleted on every device

That is expected: Syncthing synchronises deletions. It can be recovered from
versions if File Versioning is enabled for the folder — expand the folder card
and press Versions. Without versioning, only an external backup helps.

### A folder is stuck Out of Sync

Usually an edit conflict or an unreadable file:

```bash
docker compose logs --tail=200 syncthing | grep -i "error\|conflict\|permission"
```

Syncthing keeps conflicting copies next to the file, named like
`name.sync-conflict-DATE-TIME.extension`. Pick the version you want and delete
the other.

### The web interface rejects the password

The password lives in the configuration inside the volume. Reset it by editing
`config.xml` while the container is stopped:

```bash
docker compose stop syncthing
docker run --rm -it -v syncthing-config:/c alpine:3.22 \
  sh -c 'sed -i "s@<password>.*</password>@<password></password>@" /c/config/config.xml'
docker compose start syncthing
```

The interface then opens without a password — set a new one immediately.

### The node reports a different identifier after a move

The device identifier is tied to the private key in the volume. If you copied the
configuration to a second server and started both, the cluster now has two nodes
with the same ID, which is not allowed. Keep one copy and create a new node on
the other machine.

### High memory use

Memory grows with the number of files in the index. Excluding unneeded
directories through Ignore Patterns in the folder settings and increasing the
scan interval both help.

### The node does not start after an update

```bash
docker compose logs --tail=200 syncthing | grep -i "error\|migrat"
```

The index database format does not migrate downwards: the only way back to the
previous version is restoring the archive taken before the update. The files
themselves are not affected.
