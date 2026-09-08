### Контейнер не становится healthy

```bash
docker compose ps
docker compose logs --tail=200 vaultwarden
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q vaultwarden)"
```

Проверьте свободное место и доступность volume для записи. Endpoint `/alive`
проверяет не только HTTP, но и соединение с базой данных.

### Web vault сообщает о небезопасном контексте

Удалённый web vault требует HTTPS для Web Crypto API. Проверьте, что
`VAULTWARDEN_DOMAIN` начинается с `https://`, сертификат содержит полную цепочку,
а reverse proxy передаёт `Host` и `X-Forwarded-Proto`. HTTP допустим только через
локальный `localhost` во время первоначальной настройки.

### Клиенты не синхронизируются мгновенно

WebSocket использует основной порт и путь `/notifications/hub`. Проверьте
заголовки `Upgrade` и `Connection` в Nginx. Caddy и Traefik поддерживают upgrade
автоматически. Мобильные push-уведомления требуют отдельной upstream-настройки и
не проверяются этим рецептом.

### Нельзя зарегистрировать пользователя

Это безопасное поведение по умолчанию. Временно установите
`VAULTWARDEN_SIGNUPS_ALLOWED=true`, выполните `docker compose up -d`, создайте
нужную учётную запись через защищённое соединение и сразу верните `false`.

### После изменения `.env` ничего не поменялось

Если раньше настройки сохранялись через `/admin`, файл `/data/config.json`
перекрывает одноимённые environment variables. Просмотрите диагностику и файл,
но не публикуйте его: в нём могут находиться токены и SMTP-пароли.

### После обновления открылась пустая установка

Убедитесь, что подключён прежний volume, и не создавайте нового пользователя:

```bash
docker compose config
docker volume inspect vaultwarden-data
docker compose exec vaultwarden ls -la /data
```

Если volume выбран ошибочно, остановите контейнер и исправьте
`VAULTWARDEN_DATA_VOLUME`. Не удаляйте старый volume до проверки backup.
