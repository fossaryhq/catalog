### 1. Проверьте сервер Ubuntu или Debian

Для этого рецепта выделите минимум 1 CPU, 256 МБ RAM и 1 ГБ локального диска;
рекомендуется 512 МБ RAM плюс место для вложений и резервных копий. Это
консервативная оценка рецепта: upstream не публикует формальные минимальные
требования. Нужны Ubuntu 22.04+ или Debian 12+ с Docker Engine и Docker Compose
v2.24+.

```bash
docker --version
docker compose version
```

### 2. Подготовьте файлы и переменные

Поместите файлы рецепта в отдельный каталог и создайте закрытый `.env`:

```bash
mkdir -p ~/services/vaultwarden
cd ~/services/vaultwarden
cp .env.example .env
chmod 600 .env
```

Укажите в `VAULTWARDEN_DOMAIN` реальный внешний URL без завершающего `/`.
`VAULTWARDEN_VERSION` закрепляет образ; `VAULTWARDEN_PORT` задаёт локальный порт;
`VAULTWARDEN_DATA_VOLUME` — имя volume; `VAULTWARDEN_SIGNUPS_ALLOWED` и
`VAULTWARDEN_INVITATIONS_ALLOWED` управляют созданием пользователей; `TZ` задаёт
часовой пояс. Все постоянные данные находятся в `/data` внутри volume.

### 3. Создайте первую учётную запись

Оставьте порт доступным только на localhost. Временно задайте в `.env`
`VAULTWARDEN_SIGNUPS_ALLOWED=true`, затем запустите контейнер:

```bash
docker compose pull
docker compose up -d
docker compose ps
ssh -L 8000:127.0.0.1:8000 user@server.example
```

Откройте `http://localhost:8000`, зарегистрируйте пользователя и сразу верните
`VAULTWARDEN_SIGNUPS_ALLOWED=false`, затем примените настройку командой
`docker compose up -d`. `localhost` считается безопасным контекстом браузера;
для любого удалённого доступа web vault требует HTTPS.

### Запуск на VPS

<!-- coverage:deployment-vps -->

На VPS оставьте bind `127.0.0.1`, закройте порт 8000 снаружи и публикуйте сервис
только через HTTPS reverse proxy. После запуска проверьте встроенный healthcheck:

```bash
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:8000/alive
```

### Доступ в локальной сети

<!-- coverage:deployment-lan -->

Без TLS используйте SSH-туннель или VPN. Если reverse proxy работает на другом
узле доверенной LAN, замените `127.0.0.1` в `compose.yaml` на конкретный LAN-адрес
сервера, ограничьте порт firewall адресом proxy и всё равно используйте HTTPS.
Не публикуйте backend на `0.0.0.0` без сетевых ограничений.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Замените `vault.example.com` в `.env` и выбранном файле из `proxy/` одним доменом.
`proxy/Caddyfile` автоматически получает сертификат;
`proxy/nginx.conf` ожидает сертификат Certbot; `proxy/traefik.yaml` использует
resolver `letsencrypt`. Все варианты передают WebSocket на основном порту. Для
Traefik в контейнере замените `127.0.0.1` на доступный ему host gateway.

Проверьте внешний endpoint: `curl --fail https://vault.example.com/alive`. Полная
цепочка сертификатов и корректный HTTPS нужны web vault и мобильным клиентам.

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает Vaultwarden, архивирует весь volume `/data` и снова запускает
контейнер. Так SQLite и WAL копируются согласованно. Архив содержит базу,
вложения, Sends, RSA-ключи и возможные секреты из `config.json`: зашифруйте его и
храните хотя бы одну копию вне сервера. Upstream рекомендует регулярные, как
минимум ежедневные, копии и периодическую проверку восстановления.

### Восстановление

<!-- coverage:restore -->

Восстановление полностью заменяет содержимое volume выбранным архивом:

```bash
./restore.sh ./backups/vaultwarden-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
curl --fail http://127.0.0.1:8000/alive
```

Перед заменой скрипт создаёт страховочную копию текущих данных. Не смешивайте
файлы из разных снимков: `db.sqlite3` и `db.sqlite3-wal`, если он присутствует,
должны относиться к одной остановленной копии.

### Обновление

<!-- coverage:update -->

Создайте backup, прочитайте release notes и проверьте совместимость клиентов.
Измените только закреплённый `VAULTWARDEN_VERSION`, затем выполните:

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 vaultwarden
```

### Откат

<!-- coverage:rollback -->

Не запускайте старый образ поверх базы, уже мигрированной новой версией. Верните
прежний `VAULTWARDEN_VERSION` в `.env`, остановите сервис и восстановите архив,
созданный перед обновлением:

```bash
docker compose pull
docker compose stop vaultwarden
./restore.sh ./backups/vaultwarden-before-update.tar.gz
docker compose up -d
```

Сверьтесь с release notes: некоторые изменения формата данных могут запретить
downgrade без восстановления всей согласованной копии `/data`.

### Остановка и полное удаление

<!-- coverage:removal -->

`docker compose down` удаляет контейнер, но сохраняет volume. Полное необратимое
удаление после проверки backup:

```bash
docker compose down
docker volume rm vaultwarden-data
rm -rf ~/services/vaultwarden
```

Источники: [официальная установка](https://github.com/dani-garcia/vaultwarden/blob/1.37.2/README.md),
[конфигурация](https://github.com/dani-garcia/vaultwarden/wiki/Configuration-overview),
[HTTPS](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-HTTPS),
[backup](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault) и
[admin page](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-admin-page).
