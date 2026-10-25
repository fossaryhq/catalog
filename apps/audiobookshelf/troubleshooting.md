# Troubleshooting

- **Setup screen or bootstrap failure:** keep the service on loopback; set a unique password of at least 16 characters and run `docker compose run --rm -T bootstrap`. A placeholder is rejected. Existing/restored accounts retain their old password.
- **Permission denied:** `/data` must be writable by UID/GID 1000. The permissions service initializes it; files copied as root may require ownership repair. Never solve this by making private data world-writable.
- **No books:** create the library at `/data/audiobooks`, verify files are present and readable, and run a native scan. This recipe includes no commercial book catalog.
- **Listener sees no library:** activate the account and grant the intended library. Verify its upload/update/delete permissions separately.
- **Playback fails through a proxy:** check that Range and streaming requests reach the server and the upstream port matches `.env`. First verify native loopback playback. TLS examples were not end-to-end tested.
- **Archive missing media:** restore rejects a database-only archive. Back up the entire volume; separately mounted media needs a separate recovery plan.
- **Restore password differs:** `.env` is bootstrap-only. Use the restored account password or the upstream password recovery procedure.

```sh
docker compose ps
docker compose logs --tail=100 audiobookshelf
```

Logs, environment files, server metadata and backups can contain private library information or credentials. Redact them before sharing. For an isolated destructive smoke on throwaway data run `./smoke-test.sh`.
