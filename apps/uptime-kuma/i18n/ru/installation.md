### 1. Проверьте сервер Ubuntu или Debian

Минимум: 1 CPU, 512 МБ RAM и 2 ГБ на локальном диске. Рекомендуется 1 ГБ RAM.
Нужны Ubuntu 22.04+ или Debian 12+ с Docker Engine и Docker Compose v2.24+.
Отдельная база данных не требуется. Не размещайте данные на NFS: upstream
рекомендует локальную файловую систему или Docker volume.

```bash
docker --version
docker compose version
```

### 2. Подготовьте файлы и переменные

Поместите `compose.yaml`, `.env.example`, `backup.sh`, `restore.sh` и каталог
`proxy` в отдельный каталог:

```bash
mkdir -p ~/services/uptime-kuma
cd ~/services/uptime-kuma
cp .env.example .env
chmod 600 .env
```

В `.env` заданы закреплённая версия `UPTIME_KUMA_VERSION`, локальный порт
`UPTIME_KUMA_PORT`, имя volume `UPTIME_KUMA_DATA_VOLUME` и часовой пояс `TZ`.

### 3. Запустите контейнер на VPS

<!-- coverage:deployment-vps -->

```bash
docker compose pull
docker compose up -d
docker compose ps
```

Образ содержит healthcheck. При первом запуске контейнер может несколько минут
иметь статус `starting`. Порт по умолчанию доступен только на `127.0.0.1`.

### 4. Первоначальная настройка через SSH

```bash
ssh -L 3001:127.0.0.1:3001 user@server.example
```

Откройте `http://localhost:3001`, создайте администратора и сохраните пароль в
менеджере паролей.

### Локальная сеть

<!-- coverage:deployment-lan -->

Без reverse proxy безопаснее оставить localhost bind и использовать SSH-туннель.
Если панель должна быть доступна всей доверенной LAN, замените `127.0.0.1` в
`compose.yaml` на конкретный LAN-адрес сервера, например `192.168.1.10`. Не
используйте `0.0.0.0` и закройте порт 3001 на внешнем интерфейсе firewall.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Для reverse proxy, установленного непосредственно на host, готовые примеры
находятся в `proxy/Caddyfile`, `proxy/nginx.conf` и
`proxy/traefik.yaml`. Замените `status.example.com` своим доменом. Caddy получает
сертификат автоматически; для Nginx пример предполагает сертификат Certbot;
Traefik использует resolver `letsencrypt`. После публикации включите в Uptime
Kuma параметр **Trust Proxy**. Все примеры передают WebSocket. Для Traefik в
контейнере замените `127.0.0.1` на доступный контейнеру адрес host gateway.

### Резервное копирование

<!-- coverage:backup -->

Все данные находятся в volume `uptime-kuma-data`. Запустите `./backup.sh`:

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт остановит контейнер, создаст архив в `./backups` и снова запустит его.
Храните копию архива вне сервера.

### Восстановление

<!-- coverage:restore -->

Восстановление полностью заменяет содержимое volume выбранным архивом:

```bash
./restore.sh ./backups/uptime-kuma-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
```

Перед восстановлением скрипт создаёт страховочную копию текущих данных.

### Обновление

<!-- coverage:update -->

Создайте backup, прочитайте release notes, измените `UPTIME_KUMA_VERSION` в
`.env`, затем выполните:

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 uptime-kuma
```

### Откат

<!-- coverage:rollback -->

Верните прежнюю `UPTIME_KUMA_VERSION` в `.env` и запустите `docker compose pull`
и `docker compose up -d`. Если новая версия успела мигрировать базу, сначала
верните старый образ, затем восстановите созданный перед обновлением архив через
`restore.sh`. Между major-версиями сверяйтесь с release notes upstream.

### Полное удаление

<!-- coverage:removal -->

Сохранить данные: `docker compose down`. Удалить контейнер и все данные
безвозвратно:

```bash
docker compose down
docker volume rm uptime-kuma-data
rm -rf ~/services/uptime-kuma
```

Источники: [официальная установка](https://github.com/louislam/uptime-kuma#how-to-install)
и [инструкция по обновлению](https://github.com/louislam/uptime-kuma/wiki/%F0%9F%86%99-How-to-Update).
