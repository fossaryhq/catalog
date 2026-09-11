### 1. Проверьте сервер Ubuntu или Debian

Нужны Ubuntu 22.04+ или Debian 12+, Docker Engine и Compose v2.24+. Выделите
минимум 1 CPU, 512 МБ RAM и 2 ГБ диска; рекомендуется 1 ГБ RAM и запас диска под
историю статей и backup. Официальный образ заявляет amd64, arm64 и armv7, но
этот рецепт работает только на 64 битах: на armv7 его PostgreSQL отдаёт
целочисленные столбцы 32-битному PHP строками, и FreshRSS 1.29.1 не доводит
создание пользователя до конца. См. «После успешного первого запуска нет ни
одного пользователя» в диагностике.

```bash
docker --version
docker compose version
```

### 2. Подготовьте рецепт и независимые секреты

```bash
mkdir -p ~/services/freshrss
cd ~/services/freshrss
cp .env.example .env
chmod 600 .env
login_password="$(openssl rand -hex 24)"
api_password="$(openssl rand -hex 24)"
db_password="$(openssl rand -hex 24)"
sed -i "s|^FRESHRSS_ADMIN_PASSWORD=.*|FRESHRSS_ADMIN_PASSWORD=$login_password|" .env
sed -i "s|^FRESHRSS_ADMIN_API_PASSWORD=.*|FRESHRSS_ADMIN_API_PASSWORD=$api_password|" .env
sed -i "s|^FRESHRSS_DB_PASSWORD=.*|FRESHRSS_DB_PASSWORD=$db_password|" .env
unset login_password api_password db_password
```

Секреты состоят только из букв и цифр: entrypoint 1.29.1 выполняет first-run
option strings через shell `eval`, поэтому пробелы и shell-метасимволы здесь
недопустимы. Все три значения должны отличаться. Сохраните их в менеджере
паролей: API-клиент использует не пароль web-входа, а отдельный API password.

Все переменные `.env`:

- `FRESHRSS_PORT` — локальный web-порт, по умолчанию `8080`;
- `FRESHRSS_BASE_URL` — точный внешний URL с `https`, без завершающего `/`; отдельный поддомен надёжнее subpath;
- `FRESHRSS_ADMIN_USER` — ASCII-alphanumeric логин первого администратора, отличный от секретов и меняемый только до первой инициализации;
- `FRESHRSS_ADMIN_PASSWORD` и `FRESHRSS_ADMIN_API_PASSWORD` — независимые alphanumeric пароли form auth и Google Reader/Fever API;
- `FRESHRSS_ADMIN_EMAIL` — email первого администратора;
- `FRESHRSS_DB_PASSWORD` — отдельный обязательный пароль PostgreSQL;
- `FRESHRSS_DB_NAME` и `FRESHRSS_DB_USER` — имя базы и роли, меняются только до первого запуска;
- `FRESHRSS_LANGUAGE` — язык интерфейса, с которым первый запуск создаёт установку и администратора, по умолчанию `en`; каждый пользователь потом меняет его в «Настройки → Отображение»;
- `FRESHRSS_TIME_ZONE` — часовой пояс IANA;
- `FRESHRSS_CRON_MIN` — минуты встроенного cron; безопасное значение `13,43` обновляет ленты дважды в час без синхронного запуска в нулевую минуту;
- `FRESHRSS_TRUSTED_PROXY` — доверие forwarded client-IP и external-auth headers; безопасный default `0`, не меняйте на широкую сеть;
- `FRESHRSS_DATA_VOLUME`, `FRESHRSS_EXTENSIONS_VOLUME` и `FRESHRSS_DB_VOLUME` — имена постоянных volumes;
- `FRESHRSS_BACKUP_DIR` — каталог итоговых архивов на хосте.

`freshrss-data` хранит конфигурацию, пользователей и служебные файлы;
`freshrss-extensions` — сторонние расширения; `freshrss-database` — PostgreSQL.

### 3. Запустите детерминированную установку

```bash
docker compose config
docker compose pull
docker compose up -d --wait
docker compose exec freshrss cli/health.php
docker compose exec freshrss cli/list-users.php
```

`FRESHRSS_INSTALL` только при пустом data volume создаёт production-конфигурацию
с PostgreSQL, `form` auth, выключенным anonymous access, включённым API, языком
из `FRESHRSS_LANGUAGE` и точным base URL. `FRESHRSS_USER` создаёт администратора. Изменение этих
переменных после первой инициализации не меняет существующую учётную запись.

### Запуск на VPS

<!-- coverage:deployment-vps -->

Оставьте bind `127.0.0.1:${FRESHRSS_PORT}:80`: web доступен только HTTPS proxy на
этом хосте. PostgreSQL не имеет published port. В firewall откройте только SSH,
HTTP и HTTPS. До старта настройте DNS, замените `FRESHRSS_BASE_URL` и домен в
одном proxy-примере. Не приглашайте недоверенных пользователей: они могут
заставить сервер получать URL из внутренней сети.

### Доступ в доверенной локальной сети

<!-- coverage:deployment-lan -->

Предпочтителен SSH-туннель `ssh -L 8080:127.0.0.1:8080 user@server`; для него до
первого старта задайте `FRESHRSS_BASE_URL=http://localhost:8080`. Для постоянного
LAN-доступа замените localhost bind в Compose на конкретный private IP, задайте
совпадающий base URL и ограничьте порт firewall. Не используйте `0.0.0.0` без
сетевых ограничений.

### Домен, HTTPS и API-клиенты

<!-- coverage:deployment-domain-https -->

Используйте отдельный host вроде `https://rss.example.com` без завершающего `/` и
укажите его в `.env` и Caddy, Nginx или Traefik. Caddy получает сертификат
автоматически, Nginx ожидает Certbot, Traefik использует resolver `letsencrypt`.
Proxy сохраняет `Host`, передаёт `X-Forwarded-Proto` и `Authorization`, который
нужен некоторым Google Reader API-клиентам. FreshRSS не требует WebSocket, поэтому
upgrade-заголовки намеренно отсутствуют. Не заменяйте и не удаляйте CSP, которую
выдаёт FreshRSS; upstream прямо предупреждает не переопределять её в proxy.

`FRESHRSS_TRUSTED_PROXY=0` не доверяет forwarded client IP и заголовкам external
auth. Обычный form auth и API при точном `base_url` работают без широкого trusted
range. Если external auth действительно нужен, укажите только точный IP/CIDR
последнего защищённого proxy: лишний адрес позволяет подделать пользователя.

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает FreshRSS вместе со встроенным cron, оставляет PostgreSQL
работающим для native `pg_dump`, архивирует полные data и extensions, `.env` и
Compose, затем запускает приложение. Это согласованный полный backup. OPML
недостаточно: он не содержит статьи, пользователей, пароли feed, частоту
обновления, user agent и XPath scraping rules. Вместе с базой в архив попадает
`.env`, поэтому скрипт создаёт его с правами `0600` в каталоге `0700` — сохраните
это при копировании. Зашифруйте архив, скопируйте его за пределы сервера и
регулярно проверяйте restore.

### Восстановление

<!-- coverage:restore -->

Restore необратимо заменяет data, extensions и PostgreSQL. Используйте ту же
версию FreshRSS и активный `.env`, затем:

```bash
./restore.sh ./backups/freshrss-YYYYMMDDTHHMMSSZ.tar
docker compose exec freshrss cli/health.php
```

Скрипт сначала делает страховочный backup текущего состояния, пересоздаёт три
volumes, восстанавливает native dump и запускает FreshRSS. Сохранённый
`configuration.env` оставляется только для сравнения.

Этот цикл входит в `smoke-test.sh`: каждый плановый прогон рецепта создаёт
второго пользователя, делает backup, удаляет пользователя, восстанавливает архив
и проверяет, что `cli/list-users.php` снова его показывает. Чего проверка не
охватывает — ваши собственные данные и их объём, поэтому один раз пройдите
restore на отдельном сервере. После восстановления войдите и проверьте ленты,
категории, избранное и историю чтения: здоровый контейнер доказывает, что сервис
запустился, а не что вернулись нужные статьи.

### Обновление FreshRSS

<!-- coverage:update -->

Сделайте backup и прочитайте release notes. Замените точный тег
`freshrss/freshrss:1.29.1` на проверенную версию, не используйте `latest`, затем:

```bash
docker compose pull
docker compose up -d --wait
docker compose exec freshrss cli/health.php
docker compose logs --tail=200 freshrss
```

Миграции приложения применяются при старте. Не обновляйте FreshRSS и PostgreSQL
одновременно: это сохраняет однозначный путь отката.

### PostgreSQL major update

Тег `postgres:18-alpine` закреплён отдельно. Смена major требует нового data
volume: старый сервер не должен читать каталог новой major и наоборот. Остановите
FreshRSS, сохраните native `pg_dump` и полный data/extensions backup, создайте
новый volume с новым образом и восстановите dump. Upstream также предлагает
`cli/db-backup.php` и `cli/db-restore.php` для переносимого SQLite export каждого
пользователя. Не удаляйте старый volume до проверки новой базы.

### Откат

<!-- coverage:rollback -->

Не запускайте старый FreshRSS поверх данных после миграций. Верните прежние
точные теги FreshRSS и PostgreSQL и восстановите полный pre-update архив через
`restore.sh`. После неудачной смены PostgreSQL major подключите прежний образ
только к сохранённому старому volume либо восстановите его dump в пустой кластер
той же major.

### Остановка и полное удаление

<!-- coverage:removal -->

`docker compose down` сохраняет данные. После проверки внешнего backup удалить
всё безвозвратно:

```bash
docker compose down
docker volume rm freshrss-data freshrss-extensions freshrss-database
rm -rf ~/services/freshrss
```

Если имена volumes изменены в `.env`, подставьте фактические значения.

Источники: [Docker и first run](https://github.com/FreshRSS/FreshRSS/blob/1.29.1/Docker/README.md),
[backup и OPML](https://freshrss.github.io/FreshRSS/en/admins/05_Backup.html),
[access control и SSRF](https://freshrss.github.io/FreshRSS/en/admins/09_AccessControl.html),
[server CSP](https://freshrss.github.io/FreshRSS/en/admins/10_ServerConfig.html) и
[PostgreSQL upgrades](https://www.postgresql.org/docs/18/upgrading.html).
