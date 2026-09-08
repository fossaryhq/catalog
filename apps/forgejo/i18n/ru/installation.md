### 1. Проверьте сервер

Нужны Ubuntu 22.04+ или Debian 12+, Docker Engine и Compose v2.24+. Выделите
минимум 1 CPU, 512 МБ RAM и 5 ГБ диска; рекомендуется 1 ГБ RAM и отдельный запас
под Git-репозитории, packages и резервные копии.

```bash
docker --version
docker compose version
```

### 2. Настройте рецепт

```bash
mkdir -p ~/services/forgejo
cd ~/services/forgejo
cp .env.example .env
chmod 600 .env
openssl rand -base64 36
```

Запишите результат последней команды в `POSTGRES_PASSWORD`, замените
`git.example.com` реальным доменом и не публикуйте `.env`. `FORGEJO_HTTP_PORT` и
`FORGEJO_SSH_PORT` задают локальные порты, `FORGEJO_DOMAIN`,
`FORGEJO_SSH_DOMAIN` и `FORGEJO_ROOT_URL` — внешние адреса, `POSTGRES_DB`,
`POSTGRES_USER`, `POSTGRES_PASSWORD` — доступ к БД, `FORGEJO_DATA_VOLUME` и
`FORGEJO_DB_VOLUME` — volumes, `FORGEJO_BACKUP_DIR` — каталог архивов.

### 3. Запустите и создайте администратора

```bash
docker compose config
docker compose pull
docker compose up -d --wait
curl --fail http://127.0.0.1:3000/api/healthz
read -rsp 'Пароль администратора: ' FORGEJO_ADMIN_PASSWORD
docker compose exec forgejo forgejo admin user create --admin --must-change-password --username admin --email admin@example.com --password "$FORGEJO_ADMIN_PASSWORD"
unset FORGEJO_ADMIN_PASSWORD
```

Пароль не записывается в shell history, но кратковременно передаётся процессу
внутри контейнера; сразу смените его через UI. Открытая регистрация отключена.
Постоянные данные Forgejo находятся в `/var/lib/gitea`.

### Запуск на VPS

<!-- coverage:deployment-vps -->

Оставьте оба bind на `127.0.0.1`. Публикуйте web через HTTPS proxy. SSH сначала
проверяйте через туннель: `ssh -L 2222:127.0.0.1:2222 user@server` и затем
`ssh -p 2222 git@localhost`. Для публичного Git over SSH замените **только** bind
SSH в `compose.yaml` на адрес VPS, например `${SERVER_IP}:${FORGEJO_SSH_PORT}:2222`,
добавьте `SERVER_IP` в `.env` и разрешите этот TCP-порт в firewall. Web-порт 3000
оставьте локальным.

### Доступ в локальной сети

<!-- coverage:deployment-lan -->

Предпочтительны VPN или SSH-туннель. Если proxy находится на другом LAN-узле,
замените web bind на конкретный приватный IP сервера и разрешите соединения
только от proxy. Не используйте `0.0.0.0` без firewall.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Замените домен в `.env` и одном файле из `proxy/`. Caddy получает сертификат
автоматически, Nginx ожидает Certbot, Traefik использует resolver `letsencrypt`.
Proxy должен передавать `Host`, `X-Forwarded-Proto` и клиентский адрес. Если
Traefik работает в контейнере, замените `127.0.0.1` на доступный host gateway.

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает Forgejo, делает native `pg_dump`, архивирует полный data
volume и снова запускает сервис. Это согласует Git-репозитории, вложения и БД.
Зашифруйте архив: в нём есть приватный код, ключи и конфигурация. Храните копию
вне сервера и регулярно проверяйте восстановление.

### Восстановление

<!-- coverage:restore -->

Восстановление необратимо заменяет data volume и базу. Используйте ту же версию
Forgejo, проверьте `.env`, затем:

```bash
./restore.sh ./backups/forgejo-YYYYMMDDTHHMMSSZ.tar
docker compose ps
curl --fail http://127.0.0.1:3000/api/healthz
```

Процедура ещё не проверена практическим restore-тестом; сначала испытайте её на
отдельном сервере.

### Обновление

<!-- coverage:update -->

Создайте backup, прочитайте release notes и upgrade guide. Образ закреплён прямо
в `compose.yaml`; замените `16.0.3-rootless` на проверенную точную версию и
выполните `docker compose pull && docker compose up -d --wait`. При переходе на
новую major-ветку нужны ручная проверка требований и `forgejo doctor check --all`.

### Откат

<!-- coverage:rollback -->

Не запускайте старый образ поверх мигрированной БД. Верните прежний тег образа и
восстановите полный pre-update архив через `restore.sh`. После миграций откат без
восстановления согласованной копии не поддерживается.

### Остановка и удаление

<!-- coverage:removal -->

`docker compose down` сохраняет данные. После проверки backup полное удаление:

```bash
docker compose down
docker volume rm forgejo-data forgejo-database
rm -rf ~/services/forgejo
```

Источники: [Docker и rootless](https://forgejo.org/docs/latest/admin/installation/docker/),
[upgrade и backup](https://forgejo.org/docs/latest/admin/upgrade/) и
[configuration cheat sheet](https://forgejo.org/docs/latest/admin/config-cheat-sheet/).
