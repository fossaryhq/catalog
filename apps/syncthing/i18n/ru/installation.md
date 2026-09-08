### 1. Проверьте сервер Ubuntu или Debian

Для этого рецепта достаточно 1 ядра CPU, 256 МБ RAM и 2 ГБ диска под сам узел;
рекомендуется 512 МБ RAM. Это консервативная оценка рецепта: upstream не
публикует формальные минимальные требования, а расход памяти растёт вместе с
числом файлов в индексе. Место под сами файлы считайте отдельно: Syncthing
хранит полную копию каждой синхронизируемой папки. Нужны Ubuntu 22.04+ или
Debian 12+ с Docker Engine и Docker Compose v2.24+.

```bash
docker --version
docker compose version
```

### 2. Подготовьте файлы и переменные

```bash
mkdir -p ~/services/syncthing
cd ~/services/syncthing
cp .env.example .env
chmod 600 .env
sudo mkdir -p /srv/syncthing
sudo chown 1000:1000 /srv/syncthing
sed -i "s|^SYNCTHING_DATA_LOCATION=.*|SYNCTHING_DATA_LOCATION=/srv/syncthing|" .env
```

`SYNCTHING_VERSION` закрепляет образ; `SYNCTHING_DEVICE_NAME` — имя, которое
увидят другие узлы; `SYNCTHING_GUI_PORT` открывает веб-интерфейс только на
localhost; `SYNCTHING_SYNC_PORT` и `SYNCTHING_DISCOVERY_PORT` отвечают за обмен
данными и обнаружение в локальной сети; `SYNCTHING_DATA_LOCATION` — каталог с
синхронизируемыми файлами; `SYNCTHING_CONFIG_VOLUME` — volume с конфигурацией,
ключами устройства и базой индексов; `SYNCTHING_UID` и `SYNCTHING_GID` задают
владельца файлов; `TZ` — часовой пояс.

Права на каталог важны: контейнер работает от `1000:1000`, и без `chown`
Syncthing не сможет писать в `/srv/syncthing`.

### 3. Запустите узел и задайте пароль

```bash
docker compose pull
docker compose up -d
docker compose ps
ssh -L 8384:127.0.0.1:8384 user@server.example
```

Откройте `http://localhost:8384`. Веб-интерфейс изначально без пароля, поэтому
сразу зайдите в Actions → Settings → GUI и задайте пользователя и пароль — без
этого нельзя публиковать интерфейс наружу.

Идентификатор устройства (Actions → Show ID) — это то, чем узлы обмениваются
при знакомстве. На втором устройстве добавьте сервер по этому ID, на сервере
подтвердите запрос, затем выберите папку и отметьте, с каким устройством её
синхронизировать.

### Запуск на VPS

<!-- coverage:deployment-vps -->

На VPS веб-интерфейс остаётся на `127.0.0.1`, а порт синхронизации должен быть
доступен снаружи — иначе устройства соединятся только через публичные relay и
скорость упадёт в разы. Откройте его в firewall:

```bash
sudo ufw allow 22000/tcp
sudo ufw allow 22000/udp
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:8384/rest/noauth/health
```

Порт 21027/udp нужен только для обнаружения устройств в той же локальной сети;
на VPS его открывать не нужно.

### Доступ в локальной сети

<!-- coverage:deployment-lan -->

Внутри доверенной LAN веб-интерфейс удобно открывать через SSH-туннель или VPN.
Если reverse proxy работает на другом узле сети, замените `127.0.0.1` в
`compose.yaml` на конкретный LAN-адрес сервера и ограничьте порт firewall
адресом proxy.

Порт 21027/udp включает автоматическое обнаружение: устройства в одной сети
находят друг друга без ручного ввода адресов. Обмен данными при этом всё равно
идёт по порту 22000.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Через reverse proxy публикуется только веб-интерфейс. Порт синхронизации
работает по собственному протоколу и через HTTP-proxy не проходит: он остаётся
на 22000.

Замените `sync.example.com` в выбранном файле из `proxy/` одним доменом.
`proxy/Caddyfile` автоматически получает сертификат; `proxy/nginx.conf` ожидает
сертификат Certbot; `proxy/traefik.yaml` использует resolver `letsencrypt`. Для
Traefik в контейнере замените `127.0.0.1` на доступный ему host gateway.

Прежде чем открывать интерфейс наружу, задайте пароль в Settings → GUI. В
примере Nginx увеличен `proxy_read_timeout`: интерфейс держит долгие запросы
событий, и короткий таймаут рвёт соединение.

```bash
curl --fail https://sync.example.com/rest/noauth/health
```

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает контейнер, архивирует volume с конфигурацией и снова его
запускает. В архив попадают приватный ключ устройства, его идентификатор,
список папок и устройств и база индексов.

Синхронизируемые файлы в архив не входят — и это осознанно: их копия уже есть на
каждом узле. Важно другое: Syncthing не является резервным копированием.
Удаление файла разъезжается по всем устройствам так же быстро, как и изменение.
Для защиты от ошибочного удаления включите File Versioning в настройках папки, а
для настоящих бэкапов используйте отдельный инструмент.

Архив содержит приватный ключ: шифруйте его перед выносом с сервера.

### Восстановление

<!-- coverage:restore -->

Восстановление возвращает прежний идентификатор устройства, поэтому остальные
узлы продолжат работать без повторного добавления:

```bash
./restore.sh ./backups/syncthing-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
curl --fail http://127.0.0.1:8384/rest/noauth/health
```

Перед заменой скрипт создаёт страховочную копию текущей конфигурации. Если
каталог с файлами пуст, узел скачает их заново с других устройств; если файлы на
месте, Syncthing пересканирует их и обнаружит совпадение.

Никогда не запускайте две копии одной конфигурации одновременно: два узла с
одинаковым идентификатором конфликтуют в кластере.

### Обновление

<!-- coverage:update -->

Создайте backup и прочитайте release notes. Измените только закреплённый
`SYNCTHING_VERSION`, затем выполните:

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 syncthing
```

Узлы разных версий работают вместе, но протокол совместим не бесконечно: между
крупными версиями стоит обновлять все устройства примерно одновременно.

### Откат

<!-- coverage:rollback -->

Формат базы индексов меняется между крупными версиями и вниз не мигрирует.
Верните прежний `SYNCTHING_VERSION` в `.env` и восстановите архив, снятый до
обновления:

```bash
docker compose pull
./restore.sh ./backups/syncthing-before-update.tar.gz
docker compose up -d
```

Сами файлы при этом не страдают: в худшем случае узел заново построит индекс.

### Остановка и полное удаление

<!-- coverage:removal -->

`docker compose down` удаляет контейнер, но сохраняет конфигурацию и ключи.
Полное необратимое удаление после проверки backup:

```bash
docker compose down
docker volume rm syncthing-config
rm -rf ~/services/syncthing
```

Каталог `SYNCTHING_DATA_LOCATION` остаётся на месте: рецепт его не удаляет.
После удаления узла остальные устройства будут показывать его как отключённый,
пока вы не уберёте его из своих настроек.

Источники: [первые шаги](https://docs.syncthing.net/intro/getting-started.html),
[конфигурация](https://docs.syncthing.net/users/config.html),
[firewall и порты](https://docs.syncthing.net/users/firewall.html),
[версионирование файлов](https://docs.syncthing.net/users/versioning.html),
[reverse proxy](https://docs.syncthing.net/users/reverseproxy.html) и
[безопасность](https://docs.syncthing.net/users/security.html).
