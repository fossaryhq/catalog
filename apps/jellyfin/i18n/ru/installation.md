### 1. Проверьте сервер Ubuntu или Debian

Для этого рецепта выделите минимум 2 ядра CPU, 1 ГБ RAM и 5 ГБ диска под сам
сервер; рекомендуется 4 ГБ RAM. Это консервативная оценка рецепта: upstream не
публикует формальные минимальные требования, потому что нагрузка зависит от
сценария. Прямое воспроизведение почти не требует ресурсов, а транскодирование
одного потока 4K способно занять весь процессор. Место под медиатеку считайте
отдельно. Нужны Ubuntu 22.04+ или Debian 12+ с Docker Engine и Docker Compose
v2.24+.

```bash
docker --version
docker compose version
nproc && free -m
```

### 2. Разложите медиатеку по структуре, понятной Jellyfin

Обложки и описания подтягиваются автоматически, только если файл назван по
правилам upstream: каталог на фильм, имя с годом в скобках.

```text
/srv/media/Movies/Sintel (2010)/Sintel (2010).mkv
/srv/media/Movies/Tears of Steel (2012)/Tears of Steel (2012).mkv
/srv/media/Shows/Название сериала (2021)/Season 01/Название сериала S01E01.mkv
```

### 3. Подготовьте файлы и переменные

Поместите файлы рецепта в отдельный каталог и создайте закрытый `.env`:

```bash
mkdir -p ~/services/jellyfin
cd ~/services/jellyfin
cp .env.example .env
chmod 600 .env
sed -i "s|^JELLYFIN_MEDIA_LOCATION=.*|JELLYFIN_MEDIA_LOCATION=/srv/media|" .env
```

`JELLYFIN_VERSION` закрепляет образ; `JELLYFIN_PORT` задаёт локальный порт;
`JELLYFIN_PUBLISHED_URL` — внешний адрес, который сервер сообщает клиентам;
`JELLYFIN_MEDIA_LOCATION` — каталог с медиатекой, он подключается только для
чтения; `JELLYFIN_CONFIG_VOLUME` и `JELLYFIN_CACHE_VOLUME` — имена Docker volume;
`TZ` задаёт часовой пояс.

Настройки, база, метаданные и учётные записи лежат в volume `/config`. В
`/cache` находятся превью и временные файлы транскодирования — этот volume
восстанавливается повторным сканированием и в backup не нужен.

### 4. Пройдите мастер первичной настройки

Мастер не защищён паролем: пока администратор не создан, любой, кто откроет
порт, станет владельцем сервера. Поэтому первый запуск делайте через localhost
или SSH-туннель.

```bash
docker compose pull
docker compose up -d
docker compose ps
ssh -L 8096:127.0.0.1:8096 user@server.example
```

Откройте `http://localhost:8096`, выберите язык интерфейса, создайте
администратора и добавьте библиотеку, указав путь `/media/Movies` — это путь
внутри контейнера, а не на хосте. После сканирования проверьте, что обложки
подтянулись.

### Запуск на VPS

<!-- coverage:deployment-vps -->

На VPS оставьте bind `127.0.0.1`, закройте порт 8096 снаружи и публикуйте сервис
только через HTTPS reverse proxy. Проверьте состояние и API:

```bash
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:8096/health
```

Учитывайте, что общий vCPU почти всегда слишком слаб для транскодирования.
Держите файлы в форматах, которые клиенты играют напрямую, и следите за
разделом Dashboard → Playback, чтобы понимать, когда сервер начинает
перекодировать.

### Доступ в локальной сети

<!-- coverage:deployment-lan -->

Без TLS используйте SSH-туннель или VPN. Если reverse proxy работает на другом
узле доверенной LAN, замените `127.0.0.1` в `compose.yaml` на конкретный
LAN-адрес сервера и ограничьте порт firewall адресом proxy.

Автообнаружение сервера клиентами использует UDP-порт 7359: чтобы включить его,
добавьте `- "7359:7359/udp"` в раздел `ports`. DLNA требует `network_mode: host`
и в рецепте не включён — это осознанный отказ от сетевой изоляции контейнера, и
включать его стоит только в доверенной сети.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Замените `media.example.com` в выбранном файле из `proxy/` одним доменом и
укажите тот же адрес в `JELLYFIN_PUBLISHED_URL`. `proxy/Caddyfile` автоматически
получает сертификат; `proxy/nginx.conf` ожидает сертификат Certbot;
`proxy/traefik.yaml` использует resolver `letsencrypt`. Для Traefik в контейнере
замените `127.0.0.1` на доступный ему host gateway.

Все примеры отключают буферизацию ответа и передают WebSocket: без этого
перемотка рвётся, а клиенты теряют связь с сервером. Чтобы в журнале активности
были настоящие адреса пользователей, добавьте адрес proxy в Dashboard →
Networking → Known proxies.

```bash
curl --fail https://media.example.com/health
```

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает контейнер, архивирует весь volume `/config` и снова его
запускает. Остановка обязательна: базы SQLite копируются согласованно только у
выключенного сервера. В архив попадают настройки, пользователи, метаданные,
изображения и история просмотра.

Медиатека в архив не входит: это ваши файлы, и копировать их нужно отдельно.
Кэш также не сохраняется — он восстанавливается повторным сканированием.

Дополнительно в Jellyfin 10.11 есть собственный механизм: Dashboard → Backups →
Create Backup создаёт архив в `/config/data/backups`, не останавливая сервер. Он
удобен перед обновлением и попадает внутрь копии, созданной `backup.sh`.

### Восстановление

<!-- coverage:restore -->

Восстановление полностью заменяет содержимое `/config` выбранным архивом:

```bash
./restore.sh ./backups/jellyfin-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
curl --fail http://127.0.0.1:8096/health
```

Перед заменой скрипт создаёт страховочную копию текущих данных и очищает кэш:
превью и трансокды от прежней базы после подмены становятся недействительными.
Медиатека при этом не трогается, но пути к библиотекам в восстановленной базе
должны совпадать с текущим монтированием `/media`.

### Обновление

<!-- coverage:update -->

Создайте backup и прочитайте release notes. Измените только закреплённый
`JELLYFIN_VERSION`, затем выполните:

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 jellyfin
```

Обновляйте версии последовательно и не пропускайте мажорные релизы: миграции
базы рассчитаны на переход с предыдущей версии.

### Откат

<!-- coverage:rollback -->

В Jellyfin нет механизма понижения версии. Миграции применяются при первом же
запуске нового образа, после чего данные перестают открываться прежней версией.
Единственный путь назад — вернуть прежний `JELLYFIN_VERSION` в `.env` и
восстановить архив, снятый до обновления:

```bash
docker compose pull
./restore.sh ./backups/jellyfin-before-update.tar.gz
docker compose up -d
```

История просмотра и правки метаданных, сделанные после обновления, в таком
архиве отсутствуют.

### Остановка и полное удаление

<!-- coverage:removal -->

`docker compose down` удаляет контейнер, но сохраняет настройки. Полное
необратимое удаление после проверки backup:

```bash
docker compose down
docker volume rm jellyfin-config jellyfin-cache
rm -rf ~/services/jellyfin
```

Каталог `JELLYFIN_MEDIA_LOCATION` остаётся нетронутым: рецепт подключает его
только для чтения и никогда не удаляет.

Источники: [установка в контейнере](https://jellyfin.org/docs/general/installation/container/),
[быстрый старт](https://jellyfin.org/docs/general/quick-start),
[именование фильмов](https://jellyfin.org/docs/general/server/media/movies),
[backup и restore](https://jellyfin.org/docs/general/administration/backup-and-restore) и
[reverse proxy](https://jellyfin.org/docs/general/post-install/networking/reverse-proxy/).
