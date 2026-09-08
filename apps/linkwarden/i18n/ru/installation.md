### 1. Проверьте сервер Ubuntu или Debian

Нужны Ubuntu 22.04+ или Debian 12+, Docker Engine и Compose v2.24+. Выделите
минимум 2 CPU, 2 ГБ RAM и 5 ГБ диска; рекомендуется 4 ГБ RAM и отдельный запас
диска под web-архивы. Официальный образ заявляет amd64 и arm64.

```bash
docker --version
docker compose version
```

### 2. Подготовьте рецепт и независимые секреты

```bash
mkdir -p ~/services/linkwarden
cd ~/services/linkwarden
cp .env.example .env
chmod 600 .env
nextauth_secret="$(openssl rand -hex 32)"
postgres_password="$(openssl rand -hex 32)"
meili_key="$(openssl rand -hex 32)"
sed -i "s|^NEXTAUTH_SECRET=.*|NEXTAUTH_SECRET=$nextauth_secret|" .env
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$postgres_password|" .env
sed -i "s|^MEILI_MASTER_KEY=.*|MEILI_MASTER_KEY=$meili_key|" .env
unset nextauth_secret postgres_password meili_key
```

Все три секрета обязательны, должны отличаться и не меняться после первого
запуска. Hex-значение безопасно внутри PostgreSQL URL. Сохраните секреты в
менеджере паролей.

Все переменные `.env`:

- `LINKWARDEN_PORT` — локальный web-порт, по умолчанию `3000`;
- `LINKWARDEN_URL` — точный внешний URL основного приложения без завершающего `/`;
- `LINKWARDEN_USER_CONTENT_URL` — отдельный HTTPS origin для сохранённого HTML, желательно на другом registrable domain и без общих cookies;
- `NEXT_PUBLIC_DISABLE_REGISTRATION` — `false` только для создания первого account, после чего обязательно `true`;
- `NEXTAUTH_SECRET` — постоянный секрет сессий и токенов NextAuth;
- `POSTGRES_PASSWORD` — отдельный URL-safe пароль PostgreSQL;
- `MEILI_MASTER_KEY` — отдельный master key Meilisearch;
- `POSTGRES_DB` и `POSTGRES_USER` — имя базы и роли, меняются только до первого запуска;
- `LINKWARDEN_TIME_ZONE` — часовой пояс IANA;
- `LINKWARDEN_DATA_VOLUME`, `LINKWARDEN_DB_VOLUME` и `LINKWARDEN_MEILI_VOLUME` — имена volumes для архивов, PostgreSQL и поискового индекса;
- `LINKWARDEN_BACKUP_DIR` — каталог итоговых архивов на хосте.

`NEXTAUTH_URL` рецепт формирует как `${LINKWARDEN_URL}/api/v1/auth`, а `BASE_URL`
равен `LINKWARDEN_URL`. Не задавайте auth URL без `/api/v1/auth`.

### 3. Запустите и закройте регистрацию

```bash
docker compose config
docker compose pull
docker compose up -d --wait --wait-timeout 900
docker compose ps
curl -I http://127.0.0.1:3000/
```

Откройте `LINKWARDEN_URL`, создайте первую учётную запись, затем немедленно
задайте `NEXT_PUBLIC_DISABLE_REGISTRATION=true` и примените настройку:

```bash
docker compose up -d --force-recreate linkwarden
```

Проверьте в приватном окне, что регистрация больше недоступна. Не публикуйте
сервис до выполнения этого шага.

### Запуск на VPS

<!-- coverage:deployment-vps -->

Оставьте bind `127.0.0.1:${LINKWARDEN_PORT}:3000`: снаружи приложение доступно
только через HTTPS proxy на хосте. PostgreSQL и Meilisearch не имеют published
ports. В firewall откройте только SSH, HTTP и HTTPS. Создайте DNS для основного и
user-content origins до первого запуска.

### Доступ в доверенной локальной сети

<!-- coverage:deployment-lan -->

Предпочтителен SSH-туннель `ssh -L 3000:127.0.0.1:3000 user@server`; для него
используйте `LINKWARDEN_URL=http://localhost:3000`. Для постоянного LAN-доступа
замените localhost bind на конкретный private IP, задайте совпадающий URL и
ограничьте порт firewall. Не используйте `0.0.0.0` без сетевых ограничений.
Без HTTPS отдельная origin-изоляция сохранённого контента слабее, поэтому этот
режим подходит только доверенной сети.

### Домен, HTTPS и сохранённый HTML

<!-- coverage:deployment-domain-https -->

Укажите `LINKWARDEN_URL=https://links.example.com` и отдельный
`LINKWARDEN_USER_CONTENT_URL=https://saved.example.net`, затем замените оба host
в Caddy, Nginx или Traefik. Для лучшей изоляции используйте другой registrable
domain, а не поддомен основного приложения, и не задавайте общие parent-domain
cookies. Сертификат должен покрывать оба host; в Nginx замените пример путями к
подходящему SAN либо отдельным сертификатам. Proxy должен поддерживать WebSocket
и сохранять `Host`/`X-Forwarded-Proto`.

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает Linkwarden и Meilisearch, оставляет PostgreSQL работающим
для native `pg_dump`, архивирует `/data/data`, `/meili_data`, `.env` и Compose,
после чего запускает сервисы. UI JSON export не является полным backup: в нём
нет сохранённых страниц, документов и извлечённого текста. Архив содержит
секреты и пользовательский контент: зашифруйте его, скопируйте за пределы сервера
и регулярно проверяйте restore.

### Восстановление

<!-- coverage:restore -->

Restore необратимо заменяет приложение, PostgreSQL и индекс Meilisearch.
Используйте те же версии Linkwarden, PostgreSQL и Meilisearch и активный `.env`:

```bash
./restore.sh ./backups/linkwarden-YYYYMMDDTHHMMSSZ.tar
curl -I http://127.0.0.1:3000/
```

Скрипт сначала делает страховочный backup текущего состояния, пересоздаёт три
volumes, восстанавливает dump и запускает стек. Сохранённый `configuration.env`
оставляется только для сравнения. Практический restore ещё не проверен; сначала
испытайте копию на отдельном сервере.

### Обновление Linkwarden

<!-- coverage:update -->

Сделайте backup, прочитайте release notes и замените точный тег
`ghcr.io/linkwarden/linkwarden:v2.16.2` на проверенную версию. Не используйте
`latest` и не обновляйте одновременно PostgreSQL либо Meilisearch:

```bash
docker compose pull
docker compose up -d --wait --wait-timeout 900
curl -I http://127.0.0.1:3000/
docker compose logs --tail=200 linkwarden postgres meilisearch
```

Миграции базы выполняются при запуске приложения. PostgreSQL major update требует
нового пустого volume и восстановления native dump. Смена major Meilisearch
требует проверки его upgrade guide; храните старый volume до проверки поиска.

### Откат

<!-- coverage:rollback -->

Не запускайте старый Linkwarden поверх базы после новых migrations. Верните все
прежние точные теги и восстановите полный pre-update архив через `restore.sh`.
После неудачной смены PostgreSQL или Meilisearch подключайте прежний образ только
к сохранённому старому volume либо восстанавливайте совместимый dump/backup в
пустой volume.

### Остановка и полное удаление

<!-- coverage:removal -->

`docker compose down` сохраняет данные. После проверки внешнего backup удалить
всё безвозвратно:

```bash
docker compose down
docker volume rm linkwarden-data linkwarden-postgres linkwarden-meilisearch
rm -rf ~/services/linkwarden
```

Если имена volumes изменены в `.env`, подставьте фактические значения.

Источники: [self-hosting setup](https://docs.linkwarden.app/self-hosting/setup),
[environment variables](https://docs.linkwarden.app/self-hosting/environment-variables),
[user-content domain](https://docs.linkwarden.app/self-hosting/user-content-domain),
[release v2.16.2](https://github.com/linkwarden/linkwarden/releases/tag/v2.16.2) и
[PostgreSQL upgrades](https://www.postgresql.org/docs/16/upgrading.html).
