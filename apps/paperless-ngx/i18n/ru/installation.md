### 1. Проверьте сервер Ubuntu или Debian

Нужны Ubuntu 22.04+ или Debian 12+, Docker Engine и Compose v2.24+. Выделите
минимум 2 CPU, 2 ГБ RAM и 10 ГБ диска; рекомендуется 4 ГБ RAM. OCR кратковременно
нагружает CPU и требует дополнительное место для оригинала, PDF/A и миниатюр.

```bash
docker --version
docker compose version
```

### 2. Подготовьте рецепт и секреты

```bash
mkdir -p ~/services/paperless-ngx
cd ~/services/paperless-ngx
cp .env.example .env
chmod 600 .env
sed -i "s|^PAPERLESS_SECRET_KEY=.*|PAPERLESS_SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_urlsafe(64))')|" .env
sed -i "s|^PAPERLESS_DB_PASSWORD=.*|PAPERLESS_DB_PASSWORD=$(openssl rand -hex 32)|" .env
```

Не публикуйте `.env`. `PAPERLESS_SECRET_KEY` подписывает сессии и чувствительные
данные, `PAPERLESS_DB_PASSWORD` защищает PostgreSQL; оба обязательны. Сохраните
их в менеджере секретов и не меняйте при восстановлении существующего архива.

Все переменные `.env`:

- `PAPERLESS_PORT` — локальный web-порт, по умолчанию `8000`;
- `PAPERLESS_URL` — единственный внешний origin с `https`, без завершающего `/` и без пути; он задаёт allowed hosts, CORS и CSRF origins;
- `PAPERLESS_SECRET_KEY` — обязательный случайный ключ подписи;
- `PAPERLESS_DB_PASSWORD` — обязательный случайный пароль БД;
- `PAPERLESS_DB_NAME` и `PAPERLESS_DB_USER` — имя базы и роли, меняются только до первого запуска;
- `PAPERLESS_TIME_ZONE` — часовой пояс IANA для дат и фоновых задач;
- `PAPERLESS_OCR_LANGUAGE` — что распознавать в документе, по умолчанию `eng`; для двух языков `rus+eng`;
- `PAPERLESS_OCR_LANGUAGES` — какие пакеты tesseract доустановить при старте, поэтому `rus` сначала добавляется сюда;
- переменные `PAPERLESS_*_VOLUME` — имена volumes для data, media, export, consume, PostgreSQL и Valkey;
- `PAPERLESS_BACKUP_DIR` — каталог итоговых архивов на хосте.

`paperless-data` хранит индекс, модель классификации и служебные данные;
`paperless-media` — оригиналы, архивные версии и миниатюры; `paperless-export` —
результат exporter; `paperless-consume` — входящие файлы; остальные volumes —
кластер PostgreSQL и состояние Valkey. Ни один из них не зашифрован рецептом.

### 3. Запустите и создайте администратора

```bash
docker compose config
docker compose pull
docker compose up -d --wait
curl -I --fail http://127.0.0.1:8000/
docker compose exec webserver createsuperuser
```

Последняя команда интерактивно спрашивает имя, email и пароль: пароль не
попадает ни в `.env`, ни в shell history и не остаётся постоянной переменной
контейнера. Самостоятельная регистрация выключена. Не публикуйте сервис до
создания администратора. Посмотреть состояние: `docker compose ps` и
`docker compose logs --tail=100 webserver`.

Документы попадают в архив двумя путями: кнопкой **Загрузить документы** в
web-интерфейсе и через каталог consume, за которым следит контейнер. В этом
рецепте consume лежит в именованном volume `paperless-consume`, поэтому с хоста
в него никто не пишет напрямую — благодаря этому `backup.sh` и может его
заархивировать. Сканеру или синхронизируемому каталогу нужен bind mount вместо
volume в `compose.yaml`:

```yaml
    volumes:
      - /srv/paperless/consume:/usr/src/paperless/consume
```

Каталог сначала создайте для пользователя контейнера — он работает под uid 1000:
`sudo install -d -o 1000 -g 1000 /srv/paperless/consume`. После этого consume
остаётся за пределами резервной копии: `backup.sh` архивирует volume, названный
в `.env`, а не путь на хосте, поэтому каталог придётся включить в бэкап хоста.

### Запуск на VPS

<!-- coverage:deployment-vps -->

Оставьте bind `127.0.0.1:${PAPERLESS_PORT}:8000`: доступ к web даёт только HTTPS
reverse proxy на этом хосте. PostgreSQL и Valkey не имеют published ports. В
firewall откройте только SSH, HTTP и HTTPS. Перед первым входом замените домен в
`PAPERLESS_URL` и proxy-примере, настройте DNS и TLS.

### Доступ в доверенной локальной сети

<!-- coverage:deployment-lan -->

Без домена оставьте localhost bind и используйте туннель
`ssh -L 8000:127.0.0.1:8000 user@server`; для такого временного доступа задайте
`PAPERLESS_URL=http://localhost:8000` и пересоздайте webserver. Для постоянного
LAN-доступа замените `127.0.0.1` в `compose.yaml` на конкретный приватный адрес,
например `192.168.1.10`, задайте `PAPERLESS_URL=http://192.168.1.10:8000` и
ограничьте порт firewall. Не используйте `0.0.0.0` без сетевых ограничений.

### Домен, HTTPS и WebSockets

<!-- coverage:deployment-domain-https -->

Установите `PAPERLESS_URL=https://paperless.example.com` именно без завершающего
слеша: путь вроде `/paperless` в этой переменной запрещён. Замените домен в
`proxy/Caddyfile`, `proxy/nginx.conf` или `proxy/traefik.yaml`. Caddy получает
сертификат автоматически, Nginx ожидает Certbot, Traefik использует resolver
`letsencrypt`. Затем:

```bash
docker compose up -d --force-recreate webserver
```

Proxy должен сохранять `Host`, передавать `X-Forwarded-Proto: https` и клиентский
адрес. Статус фоновой обработки использует WebSocket `/ws/status/`: Caddy и
Traefik поддерживают upgrade автоматически, в Nginx он настроен явно. Если proxy
работает в контейнере, `127.0.0.1` означает сам proxy; укажите доступный host
gateway вместо localhost.

### Резервное копирование

<!-- coverage:backup -->

Сначала дождитесь окончания задач и убедитесь, что `consume` пуст. Затем:

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт запускает официальный `document_exporter`, сохраняет export, ещё не
поглощённые файлы consume, `.env` и Compose в один tar. Export включает документы,
миниатюры, метаданные, пользователей и точный снимок данных, но **не включает API
tokens**: после restore их нужно выпустить заново. Изменения, начавшиеся во время
export, могут не попасть в согласованный снимок, поэтому на время операции не
добавляйте документы и не меняйте метаданные. Архив содержит все документы и
секреты из `.env`, поэтому скрипт пишет его с правами `0600` в каталог `0700`:
сохраняйте эти права при копировании, шифруйте архив, держите копию за пределами
сервера и проверяйте restore.

### Восстановление

<!-- coverage:restore -->

Импорт необратимо заменяет все шесть volumes. Он поддерживается только в
полностью пустую установку **той же версии Paperless-ngx**, с теми же настройками
путей. Проверьте тег `3.1.2`, свободное место и активный `.env`, затем:

```bash
./restore.sh ./backups/paperless-ngx-YYYYMMDDTHHMMSSZ.tar
docker compose ps
docker compose exec webserver document_sanity_checker
```

Скрипт сначала делает страховочный export текущего состояния, удаляет volumes,
поднимает пустую установку и запускает `document_importer`. Сохранённый
`configuration.env` оставляется только для ручного сравнения и не заменяет
активный `.env`.

Круг проверки входит в `smoke-test.sh`: каждый плановый прогон рецепта поглощает
страницу, делает backup, удаляет документ, восстанавливает его и проверяет, что
документ и его распознанный текст вернулись, вместе с `document_sanity_checker`.
Чего это не покрывает — объём вашего собственного архива и импорт в другую
версию Paperless-ngx, поэтому один раз испытайте restore на отдельном сервере,
прежде чем на него полагаться. API tokens в export не входят: после импорта они
перестают работать, и их нужно выпустить заново. После восстановления войдите в
систему и проверьте документы, метки, корреспондентов и сохранённые
представления — здоровый контейнер доказывает, что сервис запустился, а не что
архив вернулся.

### Обновление Paperless-ngx

<!-- coverage:update -->

Дождитесь задач, сделайте backup и прочитайте release notes и инструкции по
миграции. Замените только точный тег `paperlessngx/paperless-ngx:3.1.2` на
проверенную версию, не используйте `latest`, затем:

```bash
docker compose pull
docker compose up -d --wait
docker compose logs --tail=200 webserver
docker compose exec webserver document_sanity_checker
```

Запуск применяет миграции автоматически. Не обновляйте Paperless одновременно с
PostgreSQL или Valkey: так причина ошибки и откат остаются однозначными.

### PostgreSQL major update

Тег `postgres:18-alpine` закреплён отдельно. Смена major не является обычным
`docker compose pull`: формат каталога данных может быть несовместим. Следуйте
официальной процедуре `pg_upgrade`/dump-restore PostgreSQL либо используйте
`document_exporter --data-only` и importer в новой пустой БД. Перед этим нужен
полный проверенный backup; не меняйте пути и не удаляйте старый volume до
проверки новой базы.

### Откат

<!-- coverage:rollback -->

Не запускайте старый образ поверх базы после миграций. Верните прежний точный тег
и восстановите полный pre-update export через `restore.sh`. Это откатывает БД,
documents и индекс вместе. Для неудачного PostgreSQL major update верните старый
тег и старый volume; не подключайте старый сервер к каталогу данных новой major.

### Остановка и полное удаление

<!-- coverage:removal -->

`docker compose down` сохраняет данные. После проверки внешнего backup удалить
всё безвозвратно:

```bash
docker compose down
docker volume rm paperless-data paperless-media paperless-export paperless-consume paperless-database paperless-broker
rm -rf ~/services/paperless-ngx
```

Если имена volumes изменены в `.env`, подставьте их фактические значения.

Источники: [configuration](https://github.com/paperless-ngx/paperless-ngx/blob/v3.1.2/docs/configuration.md),
[backup, exporter/importer и update](https://github.com/paperless-ngx/paperless-ngx/blob/v3.1.2/docs/administration.md),
[release 3.1.2](https://github.com/paperless-ngx/paperless-ngx/releases/tag/v3.1.2) и
[PostgreSQL major upgrades](https://www.postgresql.org/docs/18/upgrading.html).
