### 1. Проверьте сервер на Ubuntu или Debian

Подойдёт Ubuntu 22.04+ или Debian 12+ с Docker Engine и Compose v2.24+. Одного
ядра, 512 МБ RAM и 2 ГБ диска хватает на несколько сотен лент; база растёт
вместе с числом хранимых записей и скачанных иконок. Официальный образ заявляет
amd64 и arm64.

```bash
docker --version
docker compose version
```

### 2. Подготовьте рецепт и два независимых секрета

```bash
mkdir -p ~/services/miniflux
cd ~/services/miniflux
cp .env.example .env
chmod 600 .env
admin_password="$(openssl rand -hex 24)"
db_password="$(openssl rand -hex 32)"
sed -i "s|^MINIFLUX_ADMIN_PASSWORD=.*|MINIFLUX_ADMIN_PASSWORD=$admin_password|" .env
sed -i "s|^MINIFLUX_DB_PASSWORD=.*|MINIFLUX_DB_PASSWORD=$db_password|" .env
echo "пароль администратора: $admin_password"
unset admin_password db_password
```

Пароль базы подставляется внутрь `DATABASE_URL`, поэтому в нём должны быть
только буквы и цифры: `@`, `/` или `#` сломают строку подключения. Пароль
администратора — не короче 12 символов. Сохраните оба в менеджере паролей:
пароль администратора показывается здесь один раз и из базы не восстанавливается.

Все переменные `.env`:

- `MINIFLUX_PORT` — локальный web-порт, по умолчанию `8080`;
- `MINIFLUX_BASE_URL` — точный внешний адрес без завершающего `/`; из него строятся ссылки, редиректы OAuth2 и адрес Google Reader;
- `MINIFLUX_ADMIN_USER` и `MINIFLUX_ADMIN_PASSWORD` создают первую учётную запись при первом старте;
- `MINIFLUX_DB_PASSWORD` — буквенно-цифровой пароль PostgreSQL;
- `MINIFLUX_DB_NAME` и `MINIFLUX_DB_USER` — имена базы и роли, меняются только до первого запуска;
- `MINIFLUX_POLLING_FREQUENCY` — интервал опроса лент в минутах;
- `MINIFLUX_POLLING_PARSING_ERROR_LIMIT` — сколько подряд идущих ошибок разбора отключают ленту;
- `MINIFLUX_CLEANUP_ARCHIVE_READ_DAYS` — сколько дней хранятся прочитанные записи;
- `MINIFLUX_TRUSTED_PROXY_NETWORKS` — список CIDR, чьим заголовкам можно доверять; по умолчанию только loopback, пустым оставлять нельзя;
- `MINIFLUX_LOG_LEVEL` — `error`, `warning`, `info` или `debug`;
- `MINIFLUX_TIME_ZONE` — часовой пояс IANA;
- `MINIFLUX_DB_VOLUME` — имя volume с PostgreSQL;
- `MINIFLUX_BACKUP_DIR` — каталог резервных копий на хосте.

`RUN_MIGRATIONS` и `CREATE_ADMIN` жёстко заданы в рецепте как `1`. Обе операции
идемпотентны: миграции выполняются при каждом старте, а администратор создаётся,
только пока таблица пользователей пуста.

### 3. Запустите и войдите

```bash
docker compose config
docker compose pull
docker compose up -d --wait --wait-timeout 600
docker compose ps
curl --fail http://127.0.0.1:8080/healthcheck
```

`/healthcheck` отвечает `OK` только после успешного подключения к базе, поэтому
удачный запрос означает, что миграции завершились. Войдите по
`MINIFLUX_BASE_URL` под `MINIFLUX_ADMIN_USER` и добавьте ленты или импортируйте
OPML в разделе «Настройки → Импорт».

### Развёртывание на VPS

<!-- coverage:deployment-vps -->

Оставьте `127.0.0.1:${MINIFLUX_PORT}:8080`: до приложения доберётся только
HTTPS-прокси на этом же хосте. У PostgreSQL опубликованных портов нет. В
файрволе откройте SSH, HTTP и HTTPS и больше ничего. Miniflux опрашивает ленты с
сервера, поэтому исходящий HTTPS должен оставаться доступен; если с той же
машины видны внутренние сервисы, ограничьте исходящий трафик контейнера
публичными сетями.

### Доступ из доверенной локальной сети

<!-- coverage:deployment-lan -->

Лучше `ssh -L 8080:127.0.0.1:8080 user@server` и `MINIFLUX_BASE_URL=http://localhost:8080`
для этого маршрута. Для постоянного доступа по локальной сети замените привязку
к localhost одним конкретным приватным IP, приведите `MINIFLUX_BASE_URL` в
соответствие и ограничьте порт файрволом. Не привязывайте `0.0.0.0` без сетевых
ограничений: форма входа и Fever API будут отвечать на всех интерфейсах по
обычному HTTP.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Задайте `MINIFLUX_BASE_URL=https://reader.example.com`, замените хост в примере
для Caddy, Nginx или Traefik и пересоздайте контейнер. Прокси обязан передавать
заголовок `Authorization` — Caddy и Traefik делают это по умолчанию, а в примере
для Nginx это указано явно, — иначе Google Reader и Fever API будут отклонять
всех клиентов. WebSocket Miniflux не нужен. Работа из подпути возможна через
`BASE_URL`, но отдельный поддомен избавляет от переписывания путей к статике.

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает приложение, чтобы сборщик не писал во время дампа,
оставляет PostgreSQL доступным для нативного `pg_dump` и складывает сжатый дамп
вместе с `.env` и `compose.yaml`. В дампе есть всё, чем владеет Miniflux: ленты,
записи, метаданные вложений, иконки, сессии и API-ключи. Экспорт OPML резервной
копией не является — это только список подписок. Архив содержит секреты:
шифруйте его и увозите за пределы сервера.

### Восстановление

<!-- coverage:restore -->

Восстановление необратимо заменяет базу. Используйте те же версии Miniflux и
PostgreSQL и текущий `.env`:

```bash
./restore.sh ./backups/miniflux-YYYYMMDDTHHMMSSZ.tar
curl --fail http://127.0.0.1:8080/healthcheck
```

Скрипт сначала делает резервную копию заменяемого состояния, затем пересоздаёт
volume, восстанавливает дамп и поднимает стек. Архивный `configuration.env`
сохраняется только для сравнения и никогда не активируется. Практическую
проверку восстановления процедура не проходила — отрепетируйте её на отдельном
сервере, прежде чем на неё полагаться.

### Обновление Miniflux

<!-- coverage:update -->

Сделайте резервную копию и прочитайте release notes. Замените точный тег
`miniflux/miniflux:2.3.3` на проверенную версию, никогда не используйте `latest`
и не меняйте PostgreSQL тем же шагом:

```bash
./backup.sh
docker compose pull
docker compose up -d --wait --wait-timeout 600
curl --fail http://127.0.0.1:8080/healthcheck
docker compose logs --tail=200 miniflux
```

Миграции схемы выполняются автоматически при старте, потому что
`RUN_MIGRATIONS=1`.

### Мажорное обновление PostgreSQL

`postgres:18-alpine` зафиксирован независимо от приложения. Смена мажорной
версии требует нового volume: два мажора не должны делить один каталог кластера.
Сделайте резервную копию, поднимите новый мажор на пустом volume и восстановите
дамп через `restore.sh`. Старый volume держите до полной проверки новой базы.

### Откат

<!-- coverage:rollback -->

Никогда не запускайте старый Miniflux поверх базы, которую уже тронули новые
миграции. Верните предыдущий точный тег вместе с архивом, сделанным до
обновления:

```bash
docker compose down --timeout 60
./restore.sh ./backups/miniflux-BEFORE-UPDATE.tar
```

После неудачной смены PostgreSQL подключайте старый образ только к сохранённому
старому volume либо восстанавливайте совместимый дамп в пустой volume.

### Остановка и удаление

<!-- coverage:removal -->

`docker compose down` сохраняет базу. После проверки резервной копии за
пределами сервера удалите всё безвозвратно:

```bash
docker compose down
docker volume rm miniflux-database
rm -rf ~/services/miniflux
```

Если `MINIFLUX_DB_VOLUME` изменён, подставьте фактическое имя.

Источники: [установка в Docker](https://miniflux.app/docs/docker.html),
[параметры конфигурации](https://miniflux.app/docs/configuration.html),
[релиз 2.3.3](https://github.com/miniflux/v2/releases/tag/2.3.3) и
[обновление PostgreSQL](https://www.postgresql.org/docs/18/upgrading.html).
