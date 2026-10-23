## Требования и подготовка

Нужны 64-разрядные Ubuntu 22.04+ или Debian 12+, Docker Engine и Compose v2.24+. Ориентируйтесь на одно ядро CPU, минимум 1 ГБ RAM (рекомендуется 2 ГБ), 5 ГБ диска плюс документы. Оба образа выпускаются для amd64 и arm64; рецепт проверен на amd64.

```bash
mkdir -p ~/services/bookstack
cd ~/services/bookstack
# Скопируйте сюда файлы рецепта, включая backup.sh, restore.sh и proxy/.
cp .env.example .env
chmod 600 .env
# Вставьте весь результат base64:... в APP_KEY в .env.
printf 'base64:'; openssl rand -base64 32
# Два независимых пароля базы.
openssl rand -hex 32
openssl rand -hex 32
```

До запуска заполните `.env`. Все параметры:

| Параметр | Назначение |
| --- | --- |
| `BOOKSTACK_VERSION` | Закреплённый релиз, изначально `v26.09.2`; Compose добавляет префикс образа `version-`. |
| `BOOKSTACK_PORT` | Порт хоста на loopback, по умолчанию `6875`. |
| `BOOKSTACK_APP_URL` | Точный адрес в браузере со схемой и нестандартным портом. Изначально `http://localhost:6875`; за прокси укажите внешний HTTPS URL. |
| `BOOKSTACK_APP_KEY` | Уникальный ключ `base64:`, созданный выше. Сохраняйте его при обновлениях и восстановлении. |
| `BOOKSTACK_DB_PASSWORD` | Уникальный пароль пользователя приложения в БД; замените заглушку. |
| `BOOKSTACK_DB_ROOT_PASSWORD` | Другой пароль root базы; замените заглушку. |
| `PUID`, `PGID` | Владелец файлов LinuxServer, по умолчанию `1000:1000`. |
| `TZ` | Часовой пояс IANA, по умолчанию `Etc/UTC`. |
| `BOOKSTACK_CONFIG_VOLUME` | Именованный том `/config` с загрузками, приватными файлами, конфигурацией и темами. |
| `BOOKSTACK_DB_VOLUME` | Именованный том MariaDB с аккаунтами, страницами, историей и настройками. |
| `BOOKSTACK_BACKUP_DIR` | Необязательный абсолютный путь для копий; по умолчанию `backups/` рядом с рецептом. |

Не оставляйте заглушки секретов. После инициализации смена паролей в `.env` требует соответствующей смены паролей пользователей БД. Скрипты backup/restore загружают локальный `.env` как доверенную конфигурацию shell: защищайте его и используйте простые сгенерированные значения.

## Запуск и замена начальной учётной записи

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait --wait-timeout 600
curl --fail http://127.0.0.1:6875/status
# Укажите свой email и имя. --initial заменяет общеизвестный начальный аккаунт.
docker compose exec bookstack php /app/www/artisan bookstack:create-admin \
  --initial --email=you@example.com --name='Ваше имя' --generate-password
```

Сохраните выданный пароль в надёжном месте. Начальные данные upstream — `admin@admin.com` / `password`: замените аккаунт **до** предоставления сетевого доступа. Откройте точный `BOOKSTACK_APP_URL` и войдите с новыми данными. Язык меняется в профиле, MFA включается в настройках аутентификации аккаунта. Не включайте публичный доступ или открытую регистрацию, если не собираетесь делиться содержимым.

## VPS

<!-- coverage:deployment-vps -->

Оставьте 6875 на loopback, базу не публикуйте. Задайте `BOOKSTACK_APP_URL=https://docs.example.com`, направьте DNS на сервер, настройте HTTPS и разрешите в firewall только SSH/HTTP/HTTPS. Замените начальный аккаунт до включения публичного прокси. Храните зашифрованные копии вне сервера. SMTP и внешняя аутентификация требуют дополнительных настроек по документации upstream.

## Доверенная локальная сеть

<!-- coverage:deployment-lan -->

Для одного человека используйте `ssh -L 6875:127.0.0.1:6875 user@server` и адрес `http://localhost:6875` с соответствующим `BOOKSTACK_APP_URL`. Для совместного доступа поставьте HTTPS-прокси или привяжите порт к одному частному IP с ограничением firewall. Адрес браузера должен совпадать с настройкой; одной смены порта недостаточно.

## Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Выберите пример из `proxy/`: Caddy получает сертификаты сам, Nginx ожидает готовые файлы сертификата, Traefik — entry point `websecure` и resolver `letsencrypt`. Примеры работают на хосте и обращаются к `127.0.0.1:6875`; контейнерному прокси нужны общая Docker-сеть и внутренний порт приложения 80. Nginx допускает запросы до 50 МБ; лимит загрузки PHP тоже должен разрешать нужный размер файла.

Задайте точный внешний HTTPS URL до первого запуска. При смене существующего адреса сделайте копию, измените `BOOKSTACK_APP_URL`, пересоздайте приложение и обновите сохранённые ссылки:

```bash
docker compose up -d --wait --wait-timeout 600
docker compose exec bookstack php /app/www/artisan bookstack:update-url \
  http://localhost:6875 https://docs.example.com
```

## Резервная копия

<!-- coverage:backup -->

```bash
./backup.sh
```

Скрипт останавливает запись BookStack, снимает дамп MariaDB и собирает `/config`, `.env` и `compose.yaml` в один приватный `backups/bookstack-<timestamp>.tar`. MariaDB продолжает работать. Приложение, работавшее до копирования, запускается снова даже при ошибке копии. Зашифруйте архив и перенесите вне сервера: внутри документы, вложения, пароли БД и `APP_KEY`. Один дамп не восстановит файлы; один `/config` не восстановит страницы.

## Восстановление

<!-- coverage:restore -->

**Восстановление заменяет базу и всё содержимое `/config`.** Используйте только собственные доверенные архивы. Подготовьте рецепт с исходным `APP_KEY` и совместимыми версиями приложения и БД. Вручную сравните архивный `configuration.env` с `.env`; скрипт не загружает и не активирует архивную конфигурацию. На новом хосте сначала создайте контейнеры и дождитесь MariaDB.

```bash
docker compose up -d --wait --wait-timeout 600
./restore.sh ./backups/bookstack-TIMESTAMP.tar
curl --fail http://127.0.0.1:6875/status
docker compose logs --tail=100 bookstack
```

До замены скрипт проверяет обязательные файлы архива и сохраняет страховочную копию. При ошибке замены оставьте приложение остановленным и исправьте причину или повторите восстановление. Проверьте сохранённую страницу и вложение. Smoke-тест проверяет восстановление базы и файла на amd64.

## Обновление

<!-- coverage:update -->

Прочитайте примечания к релизу, выполните `./backup.sh` и перенесите архив вне сервера. Задайте в `BOOKSTACK_VERSION` точный проверенный релиз:

```bash
docker compose pull
docker compose up -d --wait --wait-timeout 600
docker compose logs --tail=100 bookstack
```

Не используйте `latest`. При запуске выполняются миграции БД. MariaDB закреплена отдельно в Compose; до смены версии изучите её процедуру обновления.

## Откат

<!-- coverage:rollback -->

Не запускайте старый BookStack на базе после миграций нового. Оставьте MariaDB работающей, остановите приложение, верните `BOOKSTACK_VERSION` и `APP_KEY` из состояния до обновления, затем пересоздайте контейнер без запуска:

```bash
docker compose stop bookstack
# Сейчас верните в .env прежнюю точную версию и исходный APP_KEY.
docker compose pull bookstack
docker compose create bookstack
./restore.sh ./backups/bookstack-BEFORE-UPDATE.tar
curl --fail http://127.0.0.1:6875/status
```

Остановленный контейнер позволяет сделать страховочную копию без запуска старого приложения на новой базе. Не понижайте версию MariaDB на существующем физическом каталоге: если версия менялась, восстановите SQL-дамп в чистый совместимый том, сохранив прежний до проверки результата.

## Остановка и удаление

<!-- coverage:removal -->

`docker compose down` удаляет контейнеры, сохраняя оба тома. После проверки копии вне сервера `docker compose down --volumes` безвозвратно удалит базу, документы, загрузки, аккаунты и конфигурацию. Удаление каталога рецепта уничтожает и локальные копии; заранее сохраните архив в другом месте.

Источники: [установка](https://www.bookstackapp.com/docs/admin/installation/), [образ и параметры LinuxServer](https://docs.linuxserver.io/images/docker-bookstack/), [backup/restore](https://www.bookstackapp.com/docs/admin/backup-restore/), [безопасность](https://www.bookstackapp.com/docs/admin/security/) и [CLI](https://www.bookstackapp.com/docs/admin/system-cli/).
