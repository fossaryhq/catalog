### 1. Проверьте сервер Ubuntu или Debian

Для этого рецепта выделите минимум 2 ядра CPU, 2 ГБ RAM и 20 ГБ диска под сам
сервер; рекомендуется 4 ГБ RAM. Это консервативная оценка рецепта: upstream
публикует требования к PHP и базе, но не к машине целиком, а расход зависит от
числа пользователей и включённых приложений. Место под файлы считайте отдельно.
Нужны Ubuntu 22.04+ или Debian 12+ с Docker Engine и Docker Compose v2.24+.

```bash
docker --version
docker compose version
nproc && free -m && df -h /srv
```

### 2. Подготовьте файлы и переменные

```bash
mkdir -p ~/services/nextcloud
cd ~/services/nextcloud
cp .env.example .env
chmod 600 .env
sudo mkdir -p /srv/nextcloud/data
sudo chown -R 33:33 /srv/nextcloud/data
sed -i "s|^NEXTCLOUD_DATA_LOCATION=.*|NEXTCLOUD_DATA_LOCATION=/srv/nextcloud/data|" .env
```

Внутри контейнера Nextcloud работает от `www-data` с UID 33, поэтому каталог
данных должен принадлежать этому пользователю.

Обязательно замените оба пароля из примера:

```bash
sed -i "s|^NEXTCLOUD_DB_PASSWORD=.*|NEXTCLOUD_DB_PASSWORD=$(openssl rand -hex 24)|" .env
sed -i "s|^NEXTCLOUD_ADMIN_PASSWORD=.*|NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 24)|" .env
```

`NEXTCLOUD_VERSION` закрепляет образ; `NEXTCLOUD_PORT` задаёт локальный порт;
`NEXTCLOUD_DATA_LOCATION` — каталог с файлами пользователей;
`NEXTCLOUD_HTML_VOLUME` и `NEXTCLOUD_DB_VOLUME` — volume с кодом и с базой;
`NEXTCLOUD_DB_*` и `NEXTCLOUD_ADMIN_*` задают доступ к базе и первую учётную
запись; `NEXTCLOUD_TRUSTED_DOMAINS` перечисляет домены, с которых разрешён вход;
`NEXTCLOUD_TRUSTED_PROXIES` и `NEXTCLOUD_OVERWRITE_*` нужны при публикации через
reverse proxy; `NEXTCLOUD_PHP_*` задают лимиты PHP; `TZ` — часовой пояс.

Пароль базы и имя пользователя меняются только до первого запуска: после
инициализации PostgreSQL переменная новую учётную запись не создаст.

### 3. Запустите стек

```bash
docker compose pull
docker compose up -d
docker compose ps
ssh -L 8080:127.0.0.1:8080 user@server.example
```

Первый запуск дольше обычного: контейнер распаковывает код и выполняет
установку. Администратор создаётся автоматически из переменных, поэтому мастера
установки в браузере не будет — откройте `http://localhost:8080` и сразу войдите.

Проверьте, что фоновые задания идут отдельным контейнером, а не через браузер:

```bash
docker compose exec -u www-data app php occ config:app:get core backgroundjobs_mode
```

Ответ должен быть `cron`.

### Запуск на VPS

<!-- coverage:deployment-vps -->

На VPS оставьте bind `127.0.0.1`, закройте порт 8080 снаружи и публикуйте сервис
только через HTTPS reverse proxy. Проверьте состояние стека:

```bash
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:8080/status.php
```

Все четыре контейнера должны быть подняты, а `app`, `database` и `redis` —
`healthy`. Учитывайте, что генерация превью и фоновые задания заметно нагружают
слабый VPS: на одном общем ядре стоит отключить генерацию превью для больших
файлов.

### Доступ в локальной сети

<!-- coverage:deployment-lan -->

Без TLS используйте SSH-туннель или VPN. Если reverse proxy работает на другом
узле доверенной LAN, замените `127.0.0.1` в `compose.yaml` на конкретный
LAN-адрес сервера, добавьте этот адрес в `NEXTCLOUD_TRUSTED_DOMAINS` и ограничьте
порт firewall адресом proxy.

Nextcloud не примет запрос с домена, которого нет в `NEXTCLOUD_TRUSTED_DOMAINS`:
вместо интерфейса вы увидите сообщение о недоверенном домене.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Замените `cloud.example.com` в выбранном файле из `proxy/` одним доменом и
пропишите его в `.env`:

```bash
NEXTCLOUD_TRUSTED_DOMAINS=cloud.example.com
NEXTCLOUD_TRUSTED_PROXIES=172.16.0.0/12
NEXTCLOUD_OVERWRITE_PROTOCOL=https
NEXTCLOUD_OVERWRITE_CLI_URL=https://cloud.example.com
```

`proxy/Caddyfile` автоматически получает сертификат; `proxy/nginx.conf` ожидает
сертификат Certbot; `proxy/traefik.yaml` использует resolver `letsencrypt`. Для
Traefik в контейнере замените `127.0.0.1` на доступный ему host gateway.

Все три примера делают две вещи, без которых Nextcloud работает неправильно:
снимают ограничение на размер загружаемого файла и перенаправляют
`/.well-known/carddav` и `/.well-known/caldav` на `/remote.php/dav` — иначе
календарь и контакты не подключаются в клиентах.

```bash
docker compose up -d
curl --fail https://cloud.example.com/status.php
```

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт включает maintenance mode, снимает дамп PostgreSQL, архивирует volume с
кодом, приложениями и `config.php`, затем выключает maintenance mode. Без
maintenance mode копия базы и файлов может разъехаться.

Файлы пользователей в архив не входят: их каталог может занимать терабайты, и
копировать его удобнее инкрементально:

```bash
rsync -a --delete /srv/nextcloud/data/ /mnt/backup/nextcloud-data/
```

Полное восстановление требует трёх частей: дампа базы, volume с кодом и каталога
файлов. Храните их согласованно и хотя бы одну копию — вне сервера.

Одна деталь, о которую спотыкаются при ручном backup: инсталлятор Nextcloud
заводит для работы отдельную роль PostgreSQL вида `oc_<имя_администратора>`, и
таблицы принадлежат ей, а не пользователю из `.env`. Поэтому `backup.sh` кроме
дампа базы выгружает и список ролей — без него дамп не встанет на чистый
PostgreSQL.

### Восстановление

<!-- coverage:restore -->

Восстановление заменяет базу и код целиком:

```bash
./restore.sh ./backups/nextcloud-YYYYMMDDTHHMMSSZ.tar
docker compose ps
curl --fail http://127.0.0.1:8080/status.php
```

Перед заменой скрипт создаёт страховочную копию текущего состояния, удаляет
volume базы и накатывает дамп на чистую базу. Каталог с файлами пользователей не
трогается: если он утрачен, восстановите его из своей копии до запуска, иначе
Nextcloud покажет записи без файлов.

После восстановления имеет смысл пересканировать файлы:

```bash
docker compose exec -u www-data app php occ files:scan --all
```

### Обновление

<!-- coverage:update -->

Создайте backup и прочитайте release notes. Обновляйтесь строго по одной
мажорной версии: перепрыгнуть с 32 на 34 нельзя, установщик остановит переход.

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 app
docker compose exec -u www-data app php occ status
```

После обновления загляните в Administration → Overview: там появляются новые
рекомендации и предупреждения, если что-то настроено не так.

### Откат

<!-- coverage:rollback -->

Миграции базы Nextcloud необратимы: старый образ не запустится на базе, которую
обновила новая версия. Верните прежний `NEXTCLOUD_VERSION` в `.env` и
восстановите архив, снятый до обновления:

```bash
docker compose pull
./restore.sh ./backups/nextcloud-before-update.tar
docker compose up -d
```

Файлы, загруженные после обновления, останутся на диске, но записей о них в
восстановленной базе не будет: верните их командой `occ files:scan --all`.

### Остановка и полное удаление

<!-- coverage:removal -->

`docker compose down` удаляет контейнеры, но сохраняет базу, код и файлы. Полное
необратимое удаление после проверки backup:

```bash
docker compose down
docker volume rm nextcloud-html nextcloud-database
sudo rm -rf /srv/nextcloud/data
rm -rf ~/services/nextcloud
```

Источники: [установка в Docker](https://github.com/nextcloud/docker#readme),
[руководство администратора](https://docs.nextcloud.com/server/latest/admin_manual/),
[reverse proxy](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/reverse_proxy_configuration.html),
[фоновые задания](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/background_jobs_configuration.html),
[кэширование и блокировки](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/caching_configuration.html) и
[backup](https://docs.nextcloud.com/server/latest/admin_manual/maintenance/backup.html).
