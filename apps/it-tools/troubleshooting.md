# Troubleshooting

- **Cannot connect:** check loopback port and the SSH tunnel. The container listens on 8080; the default published port is 8084.
- **Nginx fails:** check `config/nginx.conf`, UID 101 readability and `/tmp` paths. Do not switch to root to mask a configuration error.
- **Missing favorites or input:** state belongs to the browser; server backups do not contain it. Check origin, profile and private-browsing mode.
- **No Russian UI:** the selected upstream release has no Russian translation. Russian documentation and samples do not alter the interface.
- **Environment setting has no effect:** VITE settings apply at build time, not when the official static image starts.
- **Restore rejected:** use your complete trusted archive and matching tag; invalid Nginx and incomplete archives are rejected before replacement.

```sh
docker compose ps
docker compose logs --tail=100 it-tools
```

Do not publish production browser input or secrets from your proxy configuration. Configure any required gateway protection separately before public access.
