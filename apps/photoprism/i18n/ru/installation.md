### 1. Проверьте сервер Ubuntu или Debian

Используйте Ubuntu 22.04+ или Debian 12+ с Docker Engine и Compose v2.24+.
Выделите минимум 2 CPU, 4 ГБ RAM и 4 ГБ swap; 8 ГБ RAM рекомендуется для больших
файлов и индексации. Диск должен вмещать оригиналы, превью, sidecar и backup.

```bash
docker --version
docker compose version
free -h && df -h /srv
```

### 2. Подготовьте каталоги и секреты

```bash
mkdir -p ~/services/photoprism
sudo mkdir -p /srv/photoprism/{originals,storage,backups}
sudo chown -R "$(id -u):$(id -g)" /srv/photoprism
cd ~/services/photoprism
cp .env.example .env
chmod 600 .env
sed -i "s|^PHOTOPRISM_ADMIN_PASSWORD=.*|PHOTOPRISM_ADMIN_PASSWORD=$(openssl rand -base64 36 | tr -d '/+=')|" .env
sed -i "0,/^PHOTOPRISM_DATABASE_PASSWORD=.*/s||PHOTOPRISM_DATABASE_PASSWORD=$(openssl rand -hex 32)|" .env
sed -i "s|^PHOTOPRISM_DATABASE_ROOT_PASSWORD=.*|PHOTOPRISM_DATABASE_ROOT_PASSWORD=$(openssl rand -hex 32)|" .env
sed -i 's|^PHOTOPRISM_ORIGINALS_PATH=.*|PHOTOPRISM_ORIGINALS_PATH=/srv/photoprism/originals|' .env
sed -i 's|^PHOTOPRISM_STORAGE_PATH=.*|PHOTOPRISM_STORAGE_PATH=/srv/photoprism/storage|' .env
sed -i 's|^PHOTOPRISM_BACKUP_DIR=.*|PHOTOPRISM_BACKUP_DIR=/srv/photoprism/backups|' .env
sed -i "s|^PHOTOPRISM_UID=.*|PHOTOPRISM_UID=$(id -u)|" .env
sed -i "s|^PHOTOPRISM_GID=.*|PHOTOPRISM_GID=$(id -g)|" .env
```

Все переменные `.env`:

- `PHOTOPRISM_VERSION` — точный тег официального образа;
- `PHOTOPRISM_PORT` — локальный web-порт;
- `PHOTOPRISM_SITE_URL` — внешний URL с завершающим `/`;
- `PHOTOPRISM_ADMIN_USER` и `PHOTOPRISM_ADMIN_PASSWORD` — начальная учётная запись администратора;
- `PHOTOPRISM_DEFAULT_LOCALE` — язык нового интерфейса;
- `PHOTOPRISM_ORIGINALS_PATH` — оригинальные фото и видео;
- `PHOTOPRISM_STORAGE_PATH` — превью, кэш, sidecar, конфигурация и dumps;
- `PHOTOPRISM_BACKUP_DIR` — каталог локальных копий для `backup.sh`;
- `PHOTOPRISM_UID` и `PHOTOPRISM_GID` — пользователь, под которым образ запускает сервер; должен совпадать с владельцем каталогов выше;
- `PHOTOPRISM_INIT` — пусто по умолчанию; значение `tensorflow` качает CPU-оптимизированный TensorFlow (~500 МБ) при каждом пересоздании контейнера и до конца загрузки не поднимает web-сервер;
- `PHOTOPRISM_DATABASE_NAME`, `PHOTOPRISM_DATABASE_USER` и `PHOTOPRISM_DATABASE_PASSWORD` — база и учётная запись приложения;
- `PHOTOPRISM_DATABASE_ROOT_PASSWORD` — root MariaDB только для администрирования и restore;
- `PHOTOPRISM_DATABASE_VOLUME` — имя volume с MariaDB;
- `TZ` — часовой пояс IANA.

### 3. Запустите PhotoPrism

```bash
docker compose config
docker compose pull
docker compose up -d --wait
docker compose ps
curl --fail http://127.0.0.1:2342/api/v1/status
```

Откройте `http://localhost:2342` через SSH-туннель и войдите с данными из `.env`:

```bash
ssh -L 2342:127.0.0.1:2342 user@server.example
```

### Запуск на VPS

<!-- coverage:deployment-vps -->

Оставьте bind `127.0.0.1`, не публикуйте MariaDB и откройте firewall только для
SSH, HTTP и HTTPS. Задайте `PHOTOPRISM_SITE_URL=https://photos.example.com/`,
пересоздайте контейнер и публикуйте его только через HTTPS reverse proxy.

### Доступ в доверенной локальной сети

<!-- coverage:deployment-lan -->

Без TLS используйте SSH-туннель или VPN. Для постоянного LAN-доступа замените
`127.0.0.1` в `compose.yaml` на конкретный приватный адрес, установите такой же
origin в `PHOTOPRISM_SITE_URL` и ограничьте порт firewall. Не используйте
`0.0.0.0` без сетевых ограничений.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Замените `photos.example.com` в одном файле из `proxy/`. Caddy получает сертификат
автоматически, Nginx ожидает файлы Certbot, Traefik использует resolver
`letsencrypt`. Для proxy в контейнере localhost означает сам proxy: укажите
доступный host gateway. После изменения URL выполните:

```bash
docker compose up -d --force-recreate photoprism
curl --fail https://photos.example.com/api/v1/status
```

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает PhotoPrism, выгружает MariaDB и архивирует оригиналы и
storage в один `.tar` в `PHOTOPRISM_BACKUP_DIR`. Остановка обязательна:
индексация во время копирования оставит в базе записи о файлах, которых нет в
архиве оригиналов. Пароль root уходит в контейнер через `MYSQL_PWD`, а не через
argv, поэтому не попадает в список процессов. Архив содержит фото и пароли:
зашифруйте его, храните копию вне сервера и проверяйте restore. Встроенные
dumps БД в storage не заменяют копию оригиналов.

### Восстановление

<!-- coverage:restore -->

Восстановление необратимо заменяет оригиналы, storage и базу. Перед заменой
скрипт сам делает аварийную копию текущего состояния. Используйте ту же версию
образов, проверьте `.env`, затем:

```bash
./restore.sh ./backups/photoprism-YYYYMMDDTHHMMSSZ.tar
docker compose ps
curl --fail http://127.0.0.1:2342/api/v1/status
```

Процедура ещё не проверена практическим restore-тестом; сначала испытайте её на
отдельном сервере.

### Обновление

<!-- coverage:update -->

Создайте backup, прочитайте release notes и замените `PHOTOPRISM_VERSION` только
на проверенный точный тег, не `latest`. MariaDB обновляйте отдельно.

```bash
docker compose pull photoprism
docker compose up -d --wait photoprism
docker compose logs --tail=200 photoprism
```

### Откат

<!-- coverage:rollback -->

Не запускайте старый PhotoPrism поверх базы после миграций. Верните прежний тег
и восстановите весь pre-update архив, включая dump и storage. Новые снимки после
backup в откат не попадут; скопируйте их отдельно до замены данных.

### Остановка и полное удаление

<!-- coverage:removal -->

`docker compose down` сохраняет данные. После проверки внешнего backup удалить
всё безвозвратно можно так:

```bash
docker compose down
docker volume rm photoprism-database
sudo rm -rf /srv/photoprism
rm -rf ~/services/photoprism
```

Источники: [Docker Compose](https://docs.photoprism.app/getting-started/docker-compose/),
[параметры](https://docs.photoprism.app/getting-started/config-options/),
[backup](https://docs.photoprism.app/getting-started/advanced/backups/),
[updates](https://docs.photoprism.app/getting-started/updates/) и
[release 260728](https://github.com/photoprism/photoprism/releases/tag/260728-bbde8f452).
