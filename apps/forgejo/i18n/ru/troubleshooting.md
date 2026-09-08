### Forgejo не становится healthy

```bash
docker compose ps
docker compose logs --tail=200 forgejo database
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q forgejo)"
```

Проверьте пароль БД, свободное место и доступ к volumes. Endpoint
`/api/healthz` должен вернуть JSON со `status: pass`.

### Ошибка permission denied в `/var/lib/gitea`

Rootless-контейнер работает как UID/GID 1000. Не меняйте `user` без переноса
владельца данных. Для bind mount заранее выполните `chown -R 1000:1000`.

### В clone URL неверный домен или порт

Проверьте `FORGEJO_ROOT_URL`, `FORGEJO_DOMAIN`, `FORGEJO_SSH_DOMAIN` и
`FORGEJO_SSH_PORT`, затем пересоздайте контейнер: `docker compose up -d --force-recreate`.

### SSH недоступен извне

Это безопасное поведение: порт привязан к localhost. Сначала проверьте его через
туннель. Для публичного доступа следуйте разделу VPS, измените только SSH bind и
проверьте firewall командой `ssh -vvv -p 2222 git@git.example.com`.

### Ошибка 502 от reverse proxy

Проверьте `curl http://127.0.0.1:3000/api/healthz`, адрес upstream и доступность
localhost из контекста proxy. Контейнерный proxy не видит localhost хоста.
