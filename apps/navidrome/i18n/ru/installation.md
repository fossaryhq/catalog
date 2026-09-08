### 1. Проверьте сервер Ubuntu или Debian

Для этого рецепта достаточно 1 ядра CPU, 256 МБ RAM и 2 ГБ диска под сам сервер;
рекомендуется 512 МБ RAM. Это консервативная оценка рецепта: upstream не
публикует формальные минимальные требования. Место под музыку считайте отдельно,
плюс несколько процентов на кэш обложек. Нужны Ubuntu 22.04+ или Debian 12+ с
Docker Engine и Docker Compose v2.24+.

```bash
docker --version
docker compose version
```

### 2. Подготовьте медиатеку

Navidrome читает теги, а не имена файлов, поэтому важнее всего заполненные
`Artist`, `Album`, `Title` и номер трека. Раскладка по каталогам произвольная, но
удобнее всего исполнитель/альбом:

```text
/srv/music/Artist Name/Album Name (2019)/01 Track.mp3
/srv/music/Artist Name/Album Name (2019)/cover.jpg
```

Обложку Navidrome берёт из тега или из файла `cover.jpg`, `folder.jpg` либо
`front.jpg` рядом с треками. Поддерживаются MP3, FLAC, OGG, Opus, M4A, WavPack и
другие форматы, которые понимает ffmpeg внутри образа.

### 3. Подготовьте файлы и переменные

```bash
mkdir -p ~/services/navidrome
cd ~/services/navidrome
cp .env.example .env
chmod 600 .env
sed -i "s|^NAVIDROME_MUSIC_LOCATION=.*|NAVIDROME_MUSIC_LOCATION=/srv/music|" .env
```

`NAVIDROME_VERSION` закрепляет образ; `NAVIDROME_PORT` задаёт локальный порт;
`NAVIDROME_MUSIC_LOCATION` — каталог с музыкой, он подключается только для
чтения; `NAVIDROME_DATA_VOLUME` — volume с базой, обложками и историей
прослушиваний; `NAVIDROME_SCAN_INTERVAL` управляет автосканированием;
`NAVIDROME_LOG_LEVEL` и `NAVIDROME_SESSION_TIMEOUT` — логи и время жизни сессии;
`NAVIDROME_BASE_URL` нужен, только если сервис публикуется в подкаталоге домена;
`NAVIDROME_INSIGHTS` управляет отправкой анонимной статистики и по умолчанию
выключен; `TZ` задаёт часовой пояс.

### 4. Создайте администратора

Форма создания администратора не защищена паролем: первый, кто её откроет,
получит сервер. Поэтому первый запуск делайте через localhost или SSH-туннель.

```bash
docker compose pull
docker compose up -d
docker compose ps
ssh -L 4533:127.0.0.1:4533 user@server.example
```

Откройте `http://localhost:4533`, задайте имя пользователя и пароль. После этого
начнётся первое сканирование; в журнале контейнера видно, сколько треков
импортировано:

```bash
docker compose logs --tail=50 navidrome | grep -i scanner
```

Остальных пользователей заводит администратор в разделе Users. Мобильные и
десктопные клиенты сторонние: они подключаются к тому же адресу по Subsonic API.

### Запуск на VPS

<!-- coverage:deployment-vps -->

На VPS оставьте bind `127.0.0.1`, закройте порт 4533 снаружи и публикуйте сервис
только через HTTPS reverse proxy. Проверьте состояние и API:

```bash
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:4533/ping
curl --fail "http://127.0.0.1:4533/rest/ping?v=1.16.1&c=check&f=json"
```

Второй запрос отвечает ошибкой авторизации — это нормально: он подтверждает, что
Subsonic API работает, и показывает версию сервера.

### Доступ в локальной сети

<!-- coverage:deployment-lan -->

Без TLS используйте SSH-туннель или VPN. Если reverse proxy работает на другом
узле доверенной LAN, замените `127.0.0.1` в `compose.yaml` на конкретный
LAN-адрес сервера и ограничьте порт firewall адресом proxy. Не публикуйте
Navidrome на `0.0.0.0` без ограничений: Subsonic API передаёт учётные данные в
каждом запросе.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Замените `music.example.com` в выбранном файле из `proxy/` одним доменом.
`proxy/Caddyfile` автоматически получает сертификат; `proxy/nginx.conf` ожидает
сертификат Certbot; `proxy/traefik.yaml` использует resolver `letsencrypt`. Для
Traefik в контейнере замените `127.0.0.1` на доступный ему host gateway.

В примере Nginx отключена буферизация ответа: без этого перемотка внутри трека
работает рывками. Если сервис публикуется не в корне домена, задайте тот же
подкаталог в `NAVIDROME_BASE_URL`, иначе веб-интерфейс не найдёт свои файлы.

```bash
curl --fail https://music.example.com/ping
```

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает контейнер, архивирует volume `/data` и снова его запускает.
Остановка обязательна: база SQLite копируется согласованно только у выключенного
сервера. В архив попадают пользователи, плейлисты, оценки, история прослушиваний
и кэш обложек.

Музыка в архив не входит: это ваши файлы, и копировать их нужно отдельно.

У Navidrome есть и собственный механизм — `docker compose exec navidrome
/app/navidrome backup create --datafolder /data` создаёт снимок базы, не
останавливая сервер. Он удобен перед обновлением и попадает внутрь копии,
созданной `backup.sh`.

### Восстановление

<!-- coverage:restore -->

Восстановление полностью заменяет содержимое `/data` выбранным архивом:

```bash
./restore.sh ./backups/navidrome-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
curl --fail http://127.0.0.1:4533/ping
```

Перед заменой скрипт создаёт страховочную копию текущих данных. Музыка не
затрагивается, но пути в восстановленной базе должны совпадать с текущим
монтированием `/music`, иначе треки будут отмечены как отсутствующие до
следующего сканирования.

### Обновление

<!-- coverage:update -->

Создайте backup и прочитайте release notes. Измените только закреплённый
`NAVIDROME_VERSION`, затем выполните:

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 navidrome
```

Миграции базы применяются при первом запуске новой версии. Крупные обновления
иногда требуют полного пересканирования медиатеки — об этом пишут в release
notes.

### Откат

<!-- coverage:rollback -->

Понижение версии не поддерживается: после миграции старый образ не откроет базу.
Верните прежний `NAVIDROME_VERSION` в `.env` и восстановите архив, снятый до
обновления:

```bash
docker compose pull
./restore.sh ./backups/navidrome-before-update.tar.gz
docker compose up -d
```

Оценки и история прослушиваний, появившиеся после обновления, в таком архиве
отсутствуют.

### Остановка и полное удаление

<!-- coverage:removal -->

`docker compose down` удаляет контейнер, но сохраняет базу. Полное необратимое
удаление после проверки backup:

```bash
docker compose down
docker volume rm navidrome-data
rm -rf ~/services/navidrome
```

Каталог `NAVIDROME_MUSIC_LOCATION` остаётся нетронутым: рецепт подключает его
только для чтения и никогда не удаляет.

Источники: [установка в Docker](https://www.navidrome.org/docs/installation/docker/),
[параметры конфигурации](https://www.navidrome.org/docs/usage/configuration/options/),
[обложки и теги](https://www.navidrome.org/docs/usage/artwork/),
[backup и restore](https://www.navidrome.org/docs/usage/admin/backup/),
[анонимная статистика](https://www.navidrome.org/docs/usage/admin/insights/) и
[рекомендации по безопасности](https://www.navidrome.org/docs/usage/admin/security/).
