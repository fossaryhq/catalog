### 1. Подготовьте сервер

Нужны Ubuntu 22.04+ или Debian 12+ с Docker Engine и Docker Compose v2.24+.
Выделите минимум одно ядро CPU, 512 МБ RAM и 2 ГБ диска; для хранения журнала
запросов и нескольких списков лучше 1 ГБ RAM и 4 ГБ диска. Отдельная база не
нужна. Проверьте инструменты и занятость порта 53:

```bash
docker --version
docker compose version
sudo ss -luntp | grep ':53 ' || true
```

`systemd-resolved` часто слушает `127.0.0.53`, и это не обязательно конфликтует
с привязкой рецепта к `127.0.0.1`. Меняйте системный резолвер только при
реальном конфликте адресов. Не направляйте `/etc/resolv.conf` на Pi-hole до
его запуска.

### 2. Подготовьте рецепт

Поместите `compose.yaml`, `.env.example`, `backup.sh`, `restore.sh` и `proxy/`
в отдельный каталог и создайте приватный файл переменных:

```bash
mkdir -p ~/services/pi-hole
cd ~/services/pi-hole
cp .env.example .env
chmod 600 .env
openssl rand -hex 24
```

Замените пример `PIHOLE_WEB_PASSWORD` в `.env` сгенерированным значением.
Не запускайте рабочий сервер с паролем из примера. Переменные:

- `PIHOLE_VERSION` — закреплённый официальный тег образа;
- `PIHOLE_WEB_PASSWORD` — пароль администратора;
- `PIHOLE_DNS_BIND` — адрес хоста для TCP и UDP DNS, сначала `127.0.0.1`;
- `PIHOLE_DNS_PORT` — внешний порт DNS, обычно `53`;
- `PIHOLE_WEB_PORT` — локальный порт панели, сначала `8080`;
- `PIHOLE_VOLUME` — Docker volume со всеми постоянными данными Pi-hole;
- `TZ` — часовой пояс IANA для графиков и расписаний.

Compose устанавливает `FTLCONF_dns_listeningMode=ALL`, поскольку DNS-запросы
приходят через bridge-сеть Docker. Слушатели DHCP (67/udp), NTP (123/udp) и
встроенного HTTPS с самоподписанным сертификатом (443/tcp) не публикуются.

### 3. Запустите на VPS

<!-- coverage:deployment-vps -->

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait
docker compose ps
```

По умолчанию DNS и панель доступны только с самого хоста. На VPS оставьте DNS
на приватном адресе VPN, например WireGuard или Tailscale: задайте адрес
интерфейса в `PIHOLE_DNS_BIND`. Не используйте `0.0.0.0` или публичный адрес:
открытые резолверы используют для DNS-амплификации. К панели можно подключиться
через SSH-туннель:

```bash
ssh -L 8080:127.0.0.1:8080 user@server.example
```

Откройте `http://localhost:8080/admin/` и войдите с паролем из `.env`.
Панель Pi-hole пока доступна только на английском языке; скриншоты показывают
её настоящий интерфейс. Проверьте DNS на хосте:

```bash
dig @127.0.0.1 pi.hole
```

### Доверенная локальная сеть

<!-- coverage:deployment-lan -->

Укажите в `.env` для `PIHOLE_DNS_BIND` конкретный LAN-адрес сервера, например
`192.168.1.10`, и пересоздайте контейнер:

```bash
docker compose up -d --wait
docker compose port pi-hole 53/udp
```

Разрешите UDP и TCP 53 только из доверенной подсети. Для UFW:

```bash
sudo ufw allow from 192.168.1.0/24 to 192.168.1.10 port 53 proto udp
sudo ufw allow from 192.168.1.0/24 to 192.168.1.10 port 53 proto tcp
```

Затем задайте `192.168.1.10` как DNS-сервер в DHCP-настройках роутера или
настройте клиентов по отдельности. Проверьте с другого устройства командой
`nslookup pi.hole 192.168.1.10`. DHCP самого Pi-hole в этом рецепте не
включайте: bridge-сеть не передаёт нужные ему широковещательные пакеты.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Примеры `proxy/Caddyfile`, `proxy/nginx.conf` и `proxy/traefik.yaml` публикуют
только веб-панель; замените `dns.example.com` своим доменом. Caddy получает
сертификаты автоматически, Nginx ожидает сертификат Certbot, Traefik применяет
настроенный resolver `letsencrypt`. Если Traefik запущен в контейнере, замените
`127.0.0.1` на доступный ему адрес host gateway. Оставьте включённым вход в
Pi-hole и ограничьте доступ к панели доверенными пользователями. Обычный DNS
на порту 53 через HTTP proxy не проходит.

### Резервное копирование

<!-- coverage:backup -->

Все постоянные настройки, списки блокировки, база Gravity и журнал запросов
лежат в Docker volume `pi-hole-data` (или в имени из `PIHOLE_VOLUME`). Скрипт
ненадолго останавливает Pi-hole, чтобы SQLite-файлы сохранились согласованно:

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скопируйте полученный `./backups/pi-hole-*.tar.gz` за пределы сервера и защитите
его: архив содержит историю DNS и конфигурацию. Пароль из `.env` хранится
отдельно и тоже требует защиты. Экспорт Teleporter в интерфейсе полезен для
части настроек, но для полного восстановления нужен архив всего тома.

### Восстановление

<!-- coverage:restore -->

Восстановление заменяет всё содержимое `PIHOLE_VOLUME`. Сначала скрипт создаёт
страховочную копию текущего состояния:

```bash
./restore.sh ./backups/pi-hole-YYYYMMDDTHHMMSS.NNNNNNNNNZ.tar.gz
docker compose ps
```

Если пароль или имя тома менялись, отдельно восстановите соответствующий `.env`.

### Обновление

<!-- coverage:update -->

Прочитайте [заметки о выпуске Docker](https://github.com/pi-hole/docker-pi-hole/releases)
и создайте backup. Поменяйте `PIHOLE_VERSION` в `.env` на проверенный тег с
датой; не используйте `latest`. Затем:

```bash
./backup.sh
docker compose pull
docker compose up -d --wait
docker compose logs --tail=100 pi-hole
```

### Откат

<!-- coverage:rollback -->

Верните предыдущий закреплённый тег в `.env`, загрузите его и пересоздайте
контейнер. Если новая версия изменила `pihole.toml` или базы SQLite,
восстановите и архив до обновления: старый образ может не прочитать новые
данные.

```bash
docker compose pull
docker compose up -d --wait
./restore.sh ./backups/pi-hole-YYYYMMDDTHHMMSS.NNNNNNNNNZ.tar.gz
```

Скрипт сначала сохраняет текущее состояние, затем заменяет том. После отката
проверьте панель и DNS-запрос.

### Остановка и удаление

<!-- coverage:removal -->

`docker compose down` удаляет контейнер, сохраняя данные. После перевода
роутера и клиентов на другой DNS-сервер удалите данные командой
`docker compose down --volumes` (или удалите том с именем из `PIHOLE_VOLUME`).
Сохраните нужные внешние backup-архивы. Если удалить резолвер раньше смены DNS
у клиентов, разрешение имён перестанет работать.

Источники: [официальная установка в Docker](https://docs.pi-hole.net/docker/),
[настройки и capabilities](https://docs.pi-hole.net/docker/configuration/),
[требования к оборудованию](https://docs.pi-hole.net/main/prerequisites/) и
[конфигурация Pi-hole v6](https://docs.pi-hole.net/ftldns/configfile/).
