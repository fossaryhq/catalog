### Gatus сразу завершается

Gatus отклоняет неверную конфигурацию вместо запуска только с её частью:

```bash
docker compose ps --all
docker compose logs --tail=200 gatus
```

Частые причины — отступы YAML, повтор одной простой настройки в нескольких
файлах и неверное условие. Исправьте `config/config.yaml` и снова выполните
`docker compose up -d`.

### `/health` работает, но ни одна проверка не зелёная

`/health` доказывает только то, что Gatus отвечает. Посмотрите результат и логи:

```bash
read -r -p 'Имя пользователя: ' GATUS_USERNAME
read -r -s -p 'Пароль: ' GATUS_PASSWORD
curl --user "${GATUS_USERNAME}:${GATUS_PASSWORD}" \
  http://127.0.0.1:8080/api/v1/endpoints/statuses
docker compose logs --tail=200 gatus
```

Повторите DNS-запрос или HTTP-запрос с самого сервера. Цель, которая работает в
браузере, может быть закрыта от сервера, разрешаться там во внутренний адрес или
отдавать другой сертификат.

### Порт 8080 занят

Измените `GATUS_PORT` в `.env` и пересоздайте контейнер:

```bash
docker compose up -d
```

Также замените upstream-порт reverse proxy. Оставьте bind на `127.0.0.1`.

### Панель отвечает 401

Используйте текущий `GATUS_USERNAME` из `.env` и обычный пароль, чей хеш записан
в `GATUS_PASSWORD_BCRYPT_BASE64`. После замены пересоздайте контейнер, а не
только перезапустите процесс:

```bash
docker compose up -d --force-recreate
```

Не удаляйте блок `security`, чтобы вернуть доступ на публичном сервере. Задайте
новые данные и сначала проверьте их через localhost.

### После перезапуска исчезает история

Проверьте SQLite по адресу `/data/data.db` и ожидаемый volume:

```bash
docker compose config
docker volume inspect gatus-data
```

Если `storage.type` стал `memory`, новые результаты не сохранялись. Верните
конфигурацию и базу из backup до удаления старого volume.
