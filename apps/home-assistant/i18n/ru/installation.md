### 1. Проверьте сервер Ubuntu или Debian

Минимум: 2 CPU, 1 ГБ RAM и 8 ГБ на диске. Рекомендуется 2 ГБ RAM — расход растёт
вместе с числом интеграций, а база истории занимает место пропорционально числу
устройств. Нужны Ubuntu 22.04+ или Debian 12+ с Docker Engine и Docker Compose
v2.24+. Отдельная база данных не требуется: по умолчанию Home Assistant пишет
историю в SQLite внутри `/config`.

```bash
docker --version
docker compose version
```

### 2. Подготовьте файлы и переменные

Поместите `compose.yaml`, `.env.example`, `backup.sh`, `restore.sh` и каталог
`proxy` в отдельный каталог:

```bash
mkdir -p ~/services/home-assistant
cd ~/services/home-assistant
cp .env.example .env
chmod 600 .env
```

В `.env` заданы:

- `HOMEASSISTANT_VERSION` — закреплённый тег образа, совпадает с номером релиза;
- `HOMEASSISTANT_BIND` — адрес, на котором публикуется панель, по умолчанию `127.0.0.1`;
- `HOMEASSISTANT_PORT` — внешний порт панели, по умолчанию `8123`;
- `HOMEASSISTANT_CONFIG_VOLUME` — volume с каталогом `/config`;
- `TZ` — часовой пояс, от него зависят автоматизации по времени и графики.

Все пользовательские данные лежат в одном volume: `configuration.yaml`,
`automations.yaml`, база истории `home-assistant_v2.db`, каталог `.storage` с
учётными записями, токенами и настройками интеграций. В каталоге рецепта данных
не остаётся.

### 3. Запустите контейнер на VPS

<!-- coverage:deployment-vps -->

```bash
docker compose pull
docker compose up -d
docker compose ps
```

Первый запуск дольше обычного: контейнер разворачивает `/config` и поднимает
ядро. Дождитесь состояния `healthy` — healthcheck обращается к
`/manifest.json` внутри контейнера:

```bash
docker compose logs --tail=50 home-assistant
```

С настройками по умолчанию наружу не смотрит ни один порт: панель привязана к
`127.0.0.1`. На VPS так и должно остаться — доступ дают либо через reverse proxy
с HTTPS (шаг 6), либо через VPN, указав в `HOMEASSISTANT_BIND` адрес интерфейса
VPN.

### 4. Пройдите мастер первичной настройки

Панель доступна только локально, поэтому пробросьте порт по SSH:

```bash
ssh -L 8123:127.0.0.1:8123 user@server.example
```

Откройте `http://localhost:8123`. Мастер создаёт первую учётную запись — она
становится владельцем сервера. Задайте длинный пароль и сохраните его в
менеджере паролей: сброс пароля возможен только правкой файлов в volume.
Дальше мастер спросит название дома, местоположение и единицы измерения — от
координат зависят автоматизации по закату и восходу.

Сразу после мастера включите двухфакторную аутентификацию: аватар пользователя в
левом нижнем углу → «Безопасность» → «Многофакторная аутентификация».

### 5. Доступ из локальной сети

<!-- coverage:deployment-lan -->

Мобильным приложениям Home Assistant для Android и iOS нужен прямой адрес
сервера в локальной сети. Укажите в `.env` конкретный адрес сервера и
пересоздайте контейнер:

```bash
sed -i 's/^HOMEASSISTANT_BIND=.*/HOMEASSISTANT_BIND=192.168.1.10/' .env
docker compose up -d
docker compose port home-assistant 8123
```

Не ставьте `0.0.0.0`: на VPS это откроет панель управления домом всему
интернету. Ограничьте порт локальной подсетью:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 8123 proto tcp
```

Автоматический поиск устройств в этом рецепте не работает: контейнер живёт в
изолированной сети Compose и не видит широковещательные запросы mDNS, SSDP и
DHCP. Интеграции добавляются вручную — «Настройки» → «Устройства и службы» →
«Добавить интеграцию», с указанием IP-адреса устройства. Bluetooth и
USB-адаптеры Zigbee или Z-Wave требуют проброса устройства в контейнер и в
рецепт не включены.

### 6. Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Готовые примеры лежат в `proxy/Caddyfile`, `proxy/nginx.conf` и
`proxy/traefik.yaml`, замените в них `home.example.com` своим доменом. Caddy
получает сертификат автоматически, пример Nginx предполагает сертификат Certbot,
Traefik использует resolver `letsencrypt`. Интерфейс работает через WebSocket:
в примере Nginx за это отвечают заголовки `Upgrade` и `Connection`, без них
панель останется пустой.

Home Assistant по умолчанию отвергает проксированные запросы. Добавьте в
`configuration.yaml` блок `http` с адресом своего proxy:

```bash
docker compose exec home-assistant vi /config/configuration.yaml
```

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
```

В `trusted_proxies` попадает только адрес самого proxy. Лишняя подсеть в этом
списке позволяет подделать адрес клиента и обойти защиту от подбора пароля
([документация http](https://www.home-assistant.io/integrations/http/#use_x_forwarded_for)).
Если proxy работает в контейнере, укажите адрес его сети Docker, а не
`127.0.0.1`. Проверьте конфигурацию и перезапустите сервер:

```bash
docker compose exec home-assistant python -m homeassistant --script check_config -c /config
docker compose restart home-assistant
```

Панель управляет замками и камерами, поэтому публикуйте её только с включённой
двухфакторной аутентификацией, а на стороне proxy имеет смысл дополнительно
ограничить доступ по IP.

### Резервное копирование

<!-- coverage:backup -->

Данные лежат в volume `home-assistant-config`. Скрипт останавливает контейнер на
время архивации: история пишется в SQLite, и копия работающей базы получается
рассогласованной.

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Архив появится в `./backups`. Он содержит токены доступа, пароли интеграций и
историю состояний дома, поэтому храните копию вне сервера и в зашифрованном
виде.

У самого приложения есть встроенный механизм: «Настройки» → «Система» →
«Резервные копии». Он складывает архивы в `/config/backups`, то есть внутрь того
же volume, и защищает от ошибочной правки конфигурации, но не от потери сервера.
Скрипт и встроенные копии дополняют друг друга.

### Восстановление

<!-- coverage:restore -->

Восстановление полностью заменяет содержимое volume выбранным архивом:

```bash
./restore.sh ./backups/home-assistant-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
```

Перед распаковкой скрипт создаёт страховочную копию текущих данных. Версия
образа в `.env` должна совпадать с той, при которой создавался архив: старая
версия не обязана понимать файлы `.storage`, обновлённые новой.

### Обновление

<!-- coverage:update -->

Релизы выходят раз в месяц и регулярно содержат несовместимые изменения
интеграций. Обязательно прочитайте раздел
[Backward-incompatible changes](https://www.home-assistant.io/blog/categories/release-notes/)
в release notes своей версии, затем:

```bash
./backup.sh
sed -i 's/^HOMEASSISTANT_VERSION=.*/HOMEASSISTANT_VERSION=2026.9.0/' .env
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 home-assistant
```

Обновление из панели управления в этом варианте установки недоступно: без
Supervisor версию задаёт тег образа. Кнопка обновления Home Assistant Core в
интерфейсе не появится.

### Откат

<!-- coverage:rollback -->

Верните прежнее значение `HOMEASSISTANT_VERSION` в `.env` и выполните
`docker compose pull` и `docker compose up -d`. Работает это не всегда: при
обновлении Home Assistant переносит файлы `.storage` и схему базы истории на
новый формат, а обратной миграции нет. Если старая версия не поднимается,
восстановите архив, созданный перед обновлением:

```bash
./restore.sh ./backups/home-assistant-YYYYMMDDTHHMMSSZ.tar.gz
docker compose up -d
```

Отдельной внешней базы данных у рецепта нет, все миграции ограничены содержимым
volume.

### Полное удаление

<!-- coverage:removal -->

Сохранить данные: `docker compose down`. Удалить контейнер и все данные
безвозвратно:

```bash
docker compose down
docker volume rm home-assistant-config
rm -rf ~/services/home-assistant
```

Отдельно отзовите доступ в мобильных приложениях и удалите сервер из их
настроек: они хранят собственные долгоживущие токены. Если для устройств
создавались облачные привязки у производителей, их нужно снять на стороне
производителя.

Источники: [установка в Container](https://www.home-assistant.io/installation/linux#docker-compose),
[настройка интеграции http](https://www.home-assistant.io/integrations/http/),
[резервные копии](https://www.home-assistant.io/common-tasks/general/#backups) и
[release notes](https://www.home-assistant.io/blog/categories/release-notes/).
