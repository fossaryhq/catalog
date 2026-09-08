### 1. Проверьте сервер Ubuntu или Debian

Upstream требует минимум 2 ядра CPU и 6 ГБ RAM, рекомендует 4 ядра и 8 ГБ.
Под диск закладывайте объём библиотеки плюс 10–20 % на превью и транскоды: этот
рецепт держит и оригиналы, и сгенерированные файлы. Нужны Ubuntu 22.04+ или
Debian 12+ с Docker Engine и Docker Compose v2.24+.

```bash
docker --version
docker compose version
nproc && free -m && df -h /srv
```

Начиная с v3 контейнер машинного обучения на amd64 требует уровень
микроархитектуры x86-64-v2. Проверьте его до установки:

```bash
/usr/bin/ld.so --help | grep -m1 x86-64-v2
```

Если строка отсутствует, ML-контейнер не запустится: на таком сервере остаётся
только отключить машинное обучение и потерять умный поиск и распознавание лиц.

### 2. Подготовьте файлы и переменные

Поместите файлы рецепта в отдельный каталог и создайте закрытый `.env`:

```bash
mkdir -p ~/services/immich
cd ~/services/immich
cp .env.example .env
chmod 600 .env
```

`IMMICH_VERSION` закрепляет версию всех образов Immich; `IMMICH_PORT` задаёт
локальный порт; `IMMICH_UPLOAD_LOCATION` — каталог на хосте с оригиналами,
превью, транскодами и автоматическими дампами базы; `IMMICH_DB_VOLUME` и
`IMMICH_MODEL_CACHE_VOLUME` — имена Docker volume для PostgreSQL и кэша моделей;
`IMMICH_DB_USERNAME`, `IMMICH_DB_DATABASE_NAME` и `IMMICH_DB_PASSWORD` — доступ к
базе; `TZ` задаёт часовой пояс.

Обязательно замените пароль базы и укажите каталог библиотеки на диске с запасом
места:

```bash
sed -i "s|^IMMICH_DB_PASSWORD=.*|IMMICH_DB_PASSWORD=$(openssl rand -hex 24)|" .env
sudo mkdir -p /srv/immich/library
sed -i "s|^IMMICH_UPLOAD_LOCATION=.*|IMMICH_UPLOAD_LOCATION=/srv/immich/library|" .env
```

Пароль допускает только символы `A-Za-z0-9`. Менять его после первого запуска
нельзя без пересоздания базы, поэтому задайте значение сразу.

### 3. Создайте администратора

Оставьте порт доступным только на localhost и запустите стек:

```bash
docker compose pull
docker compose up -d
docker compose ps
ssh -L 2283:127.0.0.1:2283 user@server.example
```

Первый запуск дольше обычного: сервер применяет миграции базы. Откройте
`http://localhost:2283`, создайте учётную запись — первая становится
администратором — и пройдите мастер первичной настройки. Публичная регистрация в
Immich отключена: остальных пользователей администратор заводит в разделе
Administration → Users.

Мобильные приложения для Android и iOS подключаются к тому же адресу и включают
фоновую загрузку снимков.

### Запуск на VPS

<!-- coverage:deployment-vps -->

На VPS оставьте bind `127.0.0.1`, закройте порт 2283 снаружи и публикуйте сервис
только через HTTPS reverse proxy. Проверьте состояние стека и API:

```bash
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:2283/api/server/ping
```

Все четыре контейнера должны быть `healthy`. Машинное обучение скачивает модели
при первом задании, поэтому первые минуты после загрузки снимков нагрузка на CPU
высокая — это ожидаемо.

### Доступ в локальной сети

<!-- coverage:deployment-lan -->

Без TLS используйте SSH-туннель или VPN. Если reverse proxy работает на другом
узле доверенной LAN, замените `127.0.0.1` в `compose.yaml` на конкретный
LAN-адрес сервера и ограничьте порт firewall адресом proxy. Не публикуйте
Immich на `0.0.0.0` без сетевых ограничений: доступ к ленте означает доступ ко
всему архиву снимков и геометкам.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Замените `photos.example.com` в выбранном файле из `proxy/` одним доменом.
`proxy/Caddyfile` автоматически получает сертификат; `proxy/nginx.conf` ожидает
сертификат Certbot; `proxy/traefik.yaml` использует resolver `letsencrypt`. Для
Traefik в контейнере замените `127.0.0.1` на доступный ему host gateway.

Все три примера снимают ограничение на размер тела запроса и увеличивают
таймауты: без этого загрузка видео с телефона обрывается. Проверьте внешний
endpoint:

```bash
curl --fail https://photos.example.com/api/server/ping
```

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает `immich-server` и `immich-machine-learning`, снимает дамп
PostgreSQL через `pg_dump` и архивирует каталог библиотеки, после чего снова
запускает контейнеры. Копирование каталога данных PostgreSQL вместо дампа
upstream считает небезопасным, поэтому рецепт всегда использует дамп.

Архив содержит оригиналы, превью и всю базу с метаданными и лицами: зашифруйте
его и храните хотя бы одну копию вне сервера. Дополнительно Immich сам делает
автоматические дампы базы в `UPLOAD_LOCATION/backups` — по умолчанию ежедневно в
02:00 с хранением 14 последних; они не заменяют копию файлов.

### Восстановление

<!-- coverage:restore -->

Восстановление полностью заменяет и базу, и каталог библиотеки:

```bash
./restore.sh ./backups/immich-YYYYMMDDTHHMMSSZ.tar
docker compose ps
curl --fail http://127.0.0.1:2283/api/server/ping
```

Перед заменой скрипт создаёт страховочную копию текущих данных, затем удаляет
volume базы и накатывает дамп на чистую базу. Это требование upstream: дамп
нельзя восстанавливать поверх схемы, с которой уже работал сервер. База и файлы
должны относиться к одному снимку, иначе в ленте появятся записи без файлов.

### Обновление

<!-- coverage:update -->

Создайте backup и прочитайте release notes: Immich регулярно вносит изменения,
требующие ручных действий. Измените только закреплённый `IMMICH_VERSION`, затем
выполните:

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 immich-server
```

Обновляйте версии последовательно и не пропускайте мажорные релизы: миграции
базы рассчитаны на переход с предыдущей версии.

### Откат

<!-- coverage:rollback -->

Миграции базы Immich необратимы. Запуск старого образа поверх базы, уже
мигрированной новой версией, приводит к ошибкам запуска сервера. Верните прежний
`IMMICH_VERSION` в `.env` и восстановите архив, созданный перед обновлением:

```bash
docker compose pull
./restore.sh ./backups/immich-before-update.tar
docker compose ps
```

Снимки, загруженные после обновления, в таком архиве отсутствуют. Скопируйте их
из `UPLOAD_LOCATION` отдельно до отката, если они нужны.

### Остановка и полное удаление

<!-- coverage:removal -->

`docker compose down` удаляет контейнеры, но сохраняет базу и библиотеку. Полное
необратимое удаление после проверки backup:

```bash
docker compose down
docker volume rm immich-database immich-model-cache
sudo rm -rf /srv/immich/library
rm -rf ~/services/immich
```

Источники: [требования](https://docs.immich.app/install/requirements),
[установка через Docker Compose](https://docs.immich.app/install/docker-compose),
[переменные окружения](https://docs.immich.app/install/environment-variables),
[backup и restore](https://docs.immich.app/administration/backup-and-restore) и
[reverse proxy](https://docs.immich.app/administration/reverse-proxy).
