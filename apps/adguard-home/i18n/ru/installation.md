### 1. Проверьте сервер Ubuntu или Debian

Минимум: 1 CPU, 256 МБ RAM и 2 ГБ на диске. Рекомендуется 512 МБ RAM — расход
растёт вместе с размером кеша, журнала запросов и подключённых блок-листов.
Нужны Ubuntu 22.04+ или Debian 12+ с Docker Engine и Docker Compose v2.24+.
Отдельная база данных не требуется.

```bash
docker --version
docker compose version
```

### 2. Освободите порт 53

На Ubuntu и Debian порт 53 почти всегда занят `systemd-resolved`. Проверьте:

```bash
sudo ss -lunp | grep ':53 '
```

Если в выводе есть `systemd-resolve`, отключите его локальный слушатель, но
оставьте службу работающей — иначе сам сервер потеряет разрешение имён:

```bash
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nDNSStubListener=no\n' | sudo tee /etc/systemd/resolved.conf.d/adguardhome.conf
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved
sudo ss -lunp | grep ':53 ' || echo "порт 53 свободен"
```

Ссылка на `/run/systemd/resolve/resolv.conf` оставляет хосту рабочие
upstream-серверы. Не направляйте `/etc/resolv.conf` на сам AdGuard Home, пока он
не запущен: иначе сервер останется без DNS.

### 3. Подготовьте файлы и переменные

Поместите `compose.yaml`, `.env.example`, `backup.sh`, `restore.sh` и каталог
`proxy` в отдельный каталог:

```bash
mkdir -p ~/services/adguard-home
cd ~/services/adguard-home
cp .env.example .env
chmod 600 .env
```

В `.env` заданы:

- `ADGUARD_VERSION` — закреплённый тег образа, с префиксом `v`;
- `ADGUARD_DNS_BIND` — адрес, на котором публикуется DNS, по умолчанию `127.0.0.1`;
- `ADGUARD_DNS_PORT` — внешний порт DNS, обычно `53`;
- `ADGUARD_WEB_PORT` — локальный порт панели управления, по умолчанию `3000`;
- `ADGUARD_CONF_VOLUME` — volume с `AdGuardHome.yaml`: пользователи, upstream-серверы, правила;
- `ADGUARD_WORK_VOLUME` — volume со статистикой, журналом запросов и скачанными блок-листами;
- `TZ` — часовой пояс, от него зависят графики и расписания.

Все пользовательские данные лежат только в этих двух volume. В каталоге рецепта
никаких данных не остаётся.

### 4. Запустите контейнер на VPS

<!-- coverage:deployment-vps -->

```bash
docker compose pull
docker compose up -d
docker compose ps
```

С настройками по умолчанию наружу не смотрит ни один порт: DNS и панель
привязаны к `127.0.0.1`. На VPS так и должно остаться — доступ к резолверу
дают через VPN (WireGuard, Tailscale), указав в `ADGUARD_DNS_BIND` адрес
интерфейса VPN. Открывать порт 53 на публичном адресе нельзя: сервер станет
open resolver и будет использоваться для DNS-амплификации.

### 5. Пройдите мастер первичной настройки

Панель доступна только локально, поэтому пробросьте порт по SSH:

```bash
ssh -L 3000:127.0.0.1:3000 user@server.example
```

Откройте `http://localhost:3000`. В мастере оставьте веб-интерфейс на порту
`3000`, а DNS на порту `53` — эти номера соответствуют портам внутри контейнера
из `compose.yaml`. Если выбрать другие, healthcheck и проброс портов перестанут
совпадать с конфигурацией. Задайте имя администратора и длинный пароль,
сохраните его в менеджере паролей.

После мастера проверьте работу сервера:

```bash
docker compose exec adguard-home nslookup example.org 127.0.0.1
```

### Локальная сеть

<!-- coverage:deployment-lan -->

Чтобы устройства сети пользовались фильтрацией, DNS должен слушать на
LAN-интерфейсе. Укажите в `.env` конкретный адрес сервера и пересоздайте
контейнер:

```bash
sed -i 's/^ADGUARD_DNS_BIND=.*/ADGUARD_DNS_BIND=192.168.1.10/' .env
docker compose up -d
```

Не ставьте `0.0.0.0`: на VPS это откроет резолвер всему интернету. Закройте порт
53 на внешнем интерфейсе firewall и разрешите его только из локальной подсети:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 53 proto udp
sudo ufw allow from 192.168.1.0/24 to any port 53 proto tcp
```

Дальше пропишите адрес сервера как DNS в роутере — тогда фильтрация включится
для всех устройств сразу. Панель управления при этом остаётся на `127.0.0.1`.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Через reverse proxy публикуется только панель управления: DNS работает по своему
протоколу и через HTTP proxy не проходит. Готовые примеры лежат в
`proxy/Caddyfile`, `proxy/nginx.conf` и `proxy/traefik.yaml`, замените в них
`dns.example.com` своим доменом. Caddy получает сертификат автоматически, пример
Nginx предполагает сертификат Certbot, Traefik использует resolver
`letsencrypt`. Для Traefik в контейнере замените `127.0.0.1` на адрес host
gateway, доступный контейнеру.

Панель управления показывает историю запросов всей сети, поэтому доступ к домену
стоит дополнительно ограничить по IP или базовой авторизацией на стороне proxy.
Публиковать DNS-over-HTTPS средствами самого AdGuard Home этот рецепт не
настраивает: для этого понадобится отдельно пробросить порт 443 и передать
серверу сертификат.

### Резервное копирование

<!-- coverage:backup -->

Данные лежат в volume `adguard-home-conf` и `adguard-home-work`. Скрипт
архивирует оба сразу — конфигурация без статистики восстанавливается
рассогласованно:

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Архив появится в `./backups`. Он содержит `AdGuardHome.yaml` с логином и хешем
пароля администратора, поэтому храните копию вне сервера и в защищённом месте.

### Восстановление

<!-- coverage:restore -->

Восстановление полностью заменяет содержимое обоих volume выбранным архивом:

```bash
./restore.sh ./backups/adguard-home-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
```

Перед распаковкой скрипт создаёт страховочную копию текущих данных.

### Обновление

<!-- coverage:update -->

Отключите встроенное автообновление в панели — версия задаётся тегом образа.
Создайте backup, прочитайте release notes, измените `ADGUARD_VERSION` в `.env`
(не забудьте префикс `v`), затем выполните:

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 adguard-home
```

### Откат

<!-- coverage:rollback -->

Верните прежнее значение `ADGUARD_VERSION` в `.env` и выполните
`docker compose pull` и `docker compose up -d`. AdGuard Home хранит настройки в
`AdGuardHome.yaml` и при запуске приводит файл к формату своей версии, поэтому
после отката старый бинарник может не прочитать обновлённый конфиг. В этом
случае восстановите архив, созданный перед обновлением:

```bash
./restore.sh ./backups/adguard-home-YYYYMMDDTHHMMSSZ.tar.gz
```

Отдельной базы данных у приложения нет, миграции ограничены этим файлом.

### Полное удаление

<!-- coverage:removal -->

Сохранить данные: `docker compose down`. Удалить контейнер и все данные
безвозвратно:

```bash
docker compose down
docker volume rm adguard-home-conf adguard-home-work
rm -rf ~/services/adguard-home
```

Не забудьте вернуть прежний DNS в роутере и на устройствах, иначе сеть останется
без разрешения имён. Если отключали stub listener, верните его:

```bash
sudo rm /etc/systemd/resolved.conf.d/adguardhome.conf
sudo systemctl restart systemd-resolved
```

Источники: [установка в Docker](https://adguard-dns.io/kb/adguard-home/getting-started/#docker),
[настройка после установки](https://adguard-dns.io/kb/adguard-home/getting-started/#post-install)
и [конфигурация](https://adguard-dns.io/kb/adguard-home/configuration/).
