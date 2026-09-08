### Gitea не становится healthy

```bash
docker compose ps
docker compose logs --tail=200 gitea database
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q gitea)"
```

Проверьте пароль БД, свободное место и доступ к volumes. Endpoint
`/api/healthz` должен отвечать HTTP 200.

### Ошибка permission denied в `/data`

Официальный rootful-контейнер использует пользователя `git` с UID/GID 1000 для
постоянных данных. Не меняйте `USER_UID` и `USER_GID` без переноса владельца.
Для bind mount заранее выполните `chown -R 1000:1000`.

### В clone URL неверный домен или порт

Проверьте `GITEA_ROOT_URL`, `GITEA_DOMAIN`, `GITEA_SSH_DOMAIN` и
`GITEA_SSH_PORT`, затем пересоздайте контейнер:
`docker compose up -d --force-recreate`.

### SSH недоступен извне

Это безопасное поведение: порт привязан к localhost. Сначала проверьте его через
туннель. Для публичного доступа следуйте разделу VPS, измените только SSH bind и
проверьте firewall командой `ssh -vvv -p 2222 git@git.example.com`.

### Ошибка 502 от reverse proxy

Проверьте `curl http://127.0.0.1:3000/api/healthz`, адрес upstream и доступность
localhost из контекста proxy. Контейнерный proxy не видит localhost хоста.

### После restore не работает push

Проверьте логи и повторно создайте Git hooks:

```bash
docker compose exec gitea gitea admin regenerate hooks
docker compose exec gitea gitea doctor check --all
```
