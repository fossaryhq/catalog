### 1. Проверьте сервер Ubuntu или Debian

Минимум: 2 CPU, 1 ГБ RAM и 5 ГБ на диске. Рекомендуется 2 ГБ RAM — расход
растёт вместе с числом одновременных выполнений и размером их истории. Нужны
Ubuntu 22.04+ или Debian 12+ с Docker Engine и Docker Compose v2.24+.
PostgreSQL поднимается из этого же Compose, отдельно ставить не нужно.

```bash
docker --version
docker compose version
```

### 2. Подготовьте файлы и переменные

Поместите `compose.yaml`, `.env.example`, `backup.sh`, `restore.sh` и каталог
`proxy` в отдельный каталог:

```bash
mkdir -p ~/services/n8n
cd ~/services/n8n
cp .env.example .env
chmod 600 .env
```

Заполните два обязательных секрета — без них запускать нельзя:

```bash
sed -i "s|^N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)|" .env
sed -i "s|^N8N_DB_PASSWORD=.*|N8N_DB_PASSWORD=$(openssl rand -hex 24)|" .env
```

`N8N_ENCRYPTION_KEY` шифрует пароли и токены всех подключённых сервисов. После
первого запуска его нельзя менять: со старой базой новый ключ делает сохранённые
доступы нечитаемыми. Сохраните ключ в менеджере паролей отдельно от сервера.

Остальные переменные `.env`:

- `N8N_VERSION` — закреплённый тег образа; стабильная линия 2.36.x, теги 2.37.x на Docker Hub относятся к beta-каналу;
- `N8N_PORT` — локальный порт редактора, по умолчанию `5678`;
- `N8N_DB_NAME` и `N8N_DB_USER` — имя базы и пользователь, меняются только до первого запуска;
- `N8N_PUBLIC_HOST` и `N8N_PROTOCOL` — внешнее имя хоста и схема, попадают в ссылки интерфейса;
- `N8N_WEBHOOK_URL` — полный внешний адрес при публикации через reverse proxy;
- `N8N_SECURE_COOKIE` — отдавать ли cookie сессии только по HTTPS и на localhost;
- `N8N_PROXY_HOPS` — число reverse proxy перед n8n;
- `N8N_DIAGNOSTICS` и `N8N_VERSION_NOTIFICATIONS` — телеметрия и проверка обновлений, по умолчанию выключены;
- `N8N_EXECUTIONS_MAX_AGE_HOURS` — срок хранения истории выполнений, по умолчанию две недели;
- `N8N_DATA_VOLUME` и `N8N_DB_VOLUME` — имена Docker volume;
- `TZ` — часовой пояс, от него зависят узлы Schedule и Cron.

Данные лежат в двух volume: `n8n-data` хранит ключ шифрования, настройки и
бинарные данные выполнений, `n8n-database` — сами процессы, учётные данные и
историю. В каталоге рецепта данных не остаётся.

### 3. Запустите на VPS

<!-- coverage:deployment-vps -->

```bash
docker compose pull
docker compose up -d
docker compose ps
```

Первый запуск дольше обычного: n8n прогоняет миграции базы. Порт по умолчанию
доступен только на `127.0.0.1`, PostgreSQL наружу не публикуется вовсе.

### 4. Создайте владельца инстанса

```bash
ssh -L 5678:127.0.0.1:5678 user@server.example
```

Откройте `http://localhost:5678`, заведите учётную запись владельца и сохраните
пароль в менеджере паролей. До создания владельца интерфейс доступен без
авторизации, поэтому не публикуйте порт наружу раньше этого шага.

### Локальная сеть

<!-- coverage:deployment-lan -->

Без reverse proxy безопаснее оставить localhost bind и ходить через SSH-туннель.
Если редактор должен быть доступен доверенной LAN, замените `127.0.0.1` в
`compose.yaml` на конкретный адрес сервера, например `192.168.1.10`, и не
используйте `0.0.0.0`.

При доступе по обычному HTTP не на localhost n8n не отдаст cookie сессии, и вход
будет молча срываться. Для такого случая в `.env`:

```bash
sed -i 's/^N8N_SECURE_COOKIE=.*/N8N_SECURE_COOKIE=false/' .env
sed -i 's|^N8N_PUBLIC_HOST=.*|N8N_PUBLIC_HOST=192.168.1.10|' .env
docker compose up -d
```

Выключенный `N8N_SECURE_COOKIE` означает, что cookie сессии ходит по сети
открытым текстом. Это допустимо только внутри доверенной сети; для доступа
извне поднимайте HTTPS.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Примеры лежат в `proxy/Caddyfile`, `proxy/nginx.conf` и `proxy/traefik.yaml`,
замените в них `n8n.example.com` своим доменом. Caddy получает сертификат
автоматически, пример Nginx предполагает сертификат Certbot, Traefik использует
resolver `letsencrypt`. Для Traefik в контейнере замените `127.0.0.1` на адрес
host gateway, доступный контейнеру.

После публикации пропишите внешний адрес — иначе вебхуки будут выдавать ссылки
на `localhost`, и внешние сервисы до них не достучатся:

```bash
sed -i 's|^N8N_WEBHOOK_URL=.*|N8N_WEBHOOK_URL=https://n8n.example.com/|' .env
sed -i 's|^N8N_PUBLIC_HOST=.*|N8N_PUBLIC_HOST=n8n.example.com|' .env
sed -i 's|^N8N_PROTOCOL=.*|N8N_PROTOCOL=https|' .env
sed -i 's|^N8N_PROXY_HOPS=.*|N8N_PROXY_HOPS=1|' .env
docker compose up -d
```

Публикация вебхуков открывает наружу и редактор: он живёт на том же порту.
Ограничьте доступ по IP или базовой авторизацией на стороне proxy, если снаружи
нужны только вебхуки.

### Резервное копирование

<!-- coverage:backup -->

Скрипт останавливает n8n, снимает дамп PostgreSQL и архивирует volume с ключом
шифрования — порознь они бесполезны:

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Архив появится в `./backups`. Он содержит доступы ко всем подключённым сервисам
в расшифровываемом виде, поэтому храните копию вне сервера и шифруйте её.

### Восстановление

<!-- coverage:restore -->

Восстановление полностью заменяет базу и каталог данных выбранным архивом:

```bash
./restore.sh ./backups/n8n-YYYYMMDDTHHMMSSZ.tar
docker compose ps
```

Перед заменой скрипт создаёт страховочную копию текущего состояния. Значение
`N8N_ENCRYPTION_KEY` в `.env` должно совпадать с тем, при котором делался архив,
иначе процессы восстановятся, а учётные данные к сервисам — нет.

### Обновление

<!-- coverage:update -->

Создайте backup, прочитайте release notes, измените `N8N_VERSION` в `.env`,
затем выполните:

```bash
./backup.sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 n8n
```

Не перепрыгивайте через мажорные версии: миграции рассчитаны на
последовательное обновление. Обновляйтесь в пределах стабильной линии 2.36.x,
пока 2.37.x остаётся beta-каналом.

### Откат

<!-- coverage:rollback -->

Верните прежнюю `N8N_VERSION` в `.env` и выполните `docker compose pull` и
`docker compose up -d`. Если новая версия успела прогнать миграции базы, одного
отката образа мало: старый n8n не умеет читать новую схему. В этом случае
восстановите архив, созданный перед обновлением:

```bash
./restore.sh ./backups/n8n-YYYYMMDDTHHMMSSZ.tar
```

Поэтому backup перед каждым обновлением обязателен: только он делает откат
возможным.

### Полное удаление

<!-- coverage:removal -->

Сохранить данные: `docker compose down`. Удалить контейнеры и все данные
безвозвратно:

```bash
docker compose down
docker volume rm n8n-data n8n-database
rm -rf ~/services/n8n
```

Отключите вебхуки во внешних сервисах до удаления, иначе они продолжат
стучаться на несуществующий адрес.

Источники: [установка в Docker](https://docs.n8n.io/hosting/installation/docker/),
[переменные окружения](https://docs.n8n.io/hosting/configuration/environment-variables/)
и [обновление](https://docs.n8n.io/hosting/installation/updating/).
