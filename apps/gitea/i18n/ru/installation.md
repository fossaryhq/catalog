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
mkdir -p ~/services/gitea
cd ~/services/gitea
cp .env.example .env
chmod 600 .env
openssl rand -base64 36
```

Запишите результат последней команды в `POSTGRES_PASSWORD`, замените
`git.example.com` реальным доменом и не публикуйте `.env`. `GITEA_HTTP_PORT` и
`GITEA_SSH_PORT` задают локальные порты; `GITEA_DOMAIN`, `GITEA_SSH_DOMAIN` и
`GITEA_ROOT_URL` — внешние адреса; `POSTGRES_DB`, `POSTGRES_USER` и
`POSTGRES_PASSWORD` — доступ к БД; `GITEA_DATA_VOLUME` и `GITEA_DB_VOLUME` —
volumes; `GITEA_BACKUP_DIR` — каталог резервных копий.

### 3. Запустите и создайте администратора

```bash
docker compose config
docker compose pull
docker compose up -d --wait
curl --fail http://127.0.0.1:3000/api/healthz
read -rsp 'Пароль администратора: ' GITEA_ADMIN_PASSWORD
docker compose exec gitea gitea admin user create --admin --must-change-password --username admin --email admin@example.com --password "$GITEA_ADMIN_PASSWORD"
unset GITEA_ADMIN_PASSWORD
```

Пароль не записывается в shell history, но кратковременно передаётся процессу
внутри контейнера; сразу смените его через UI. Открытая регистрация отключена.
Постоянные данные Gitea находятся в `/data`.

### Запуск на VPS

<!-- coverage:deployment-vps -->

Оставьте оба bind на `127.0.0.1`. Публикуйте web через HTTPS proxy. SSH сначала
проверяйте через туннель: `ssh -L 2222:127.0.0.1:2222 user@server`, затем
`ssh -p 2222 git@localhost`. Для публичного Git over SSH замените **только** bind
SSH в `compose.yaml` на конкретный адрес VPS, например
`${SERVER_IP}:${GITEA_SSH_PORT}:22`, добавьте `SERVER_IP` в `.env` и разрешите
этот TCP-порт в firewall. Web-порт 3000 оставьте локальным.

### Доступ в локальной сети

<!-- coverage:deployment-lan -->

Предпочтительны VPN или SSH-туннель. Если proxy находится на другом LAN-узле,
замените web bind на конкретный приватный IP сервера и разрешите соединения
только от proxy. Не используйте `0.0.0.0` без firewall.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Замените домен в `.env` и одном файле из `proxy/`. Caddy получает сертификат
автоматически, Nginx ожидает файлы Certbot, Traefik использует resolver
`letsencrypt`. Proxy должен сохранять URI и передавать `Host`,
`X-Forwarded-Proto` и клиентский адрес. Если Traefik работает в контейнере,
замените `127.0.0.1` на доступный host gateway.

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает Gitea, делает native `pg_dump`, архивирует полный data
volume и снова запускает сервис. Остановка обязательна: репозитории на диске и
описывающие их строки БД согласованы между собой только пока никто не пишет.
Архив ложится в `GITEA_BACKUP_DIR`. Зашифруйте его: в нём приватный код, ключи
и конфигурация. Храните копию вне сервера и регулярно проверяйте восстановление.

### Восстановление

<!-- coverage:restore -->

Восстановление необратимо заменяет data volume и базу. Перед заменой скрипт сам
делает аварийную копию текущего состояния. Используйте ту же версию Gitea,
проверьте `.env`, затем:

```bash
./restore.sh ./backups/gitea-YYYYMMDDTHHMMSSZ.tar
docker compose ps
curl --fail http://127.0.0.1:3000/api/healthz
```

Скрипт заканчивает вызовом `gitea admin regenerate hooks`: hook-скрипты хранят
абсолютные пути и версию бинарника, поэтому после замены data-каталога их нужно
перезаписать. Процедура ещё не проверена практическим restore-тестом; сначала
испытайте её на отдельном сервере.

### Обновление

<!-- coverage:update -->

Создайте backup, прочитайте release notes и руководство по обновлению. Образ
закреплён в `compose.yaml`: замените `1.27.3` на проверенную точную версию, при
необходимости обновите точный тег PostgreSQL и выполните
`docker compose pull && docker compose up -d --wait`. Не переключайтесь между
rootful и rootless образами: их структуры данных несовместимы.

### Откат

<!-- coverage:rollback -->

Не запускайте старый образ поверх мигрированной БД. Верните прежние точные теги
Gitea и PostgreSQL, затем восстановите весь pre-update каталог по процедуре выше.
После миграций откат без согласованной копии файлов и БД небезопасен.

### Остановка и удаление

<!-- coverage:removal -->

`docker compose down` сохраняет данные. После проверки внешнего backup полное
удаление выполняется так:

```bash
docker compose down
docker volume rm gitea-data gitea-database
rm -rf ~/services/gitea
```

Источники: [официальная установка с Docker](https://docs.gitea.com/installation/install-with-docker),
[backup и restore](https://docs.gitea.com/administration/backup-and-restore),
[reverse proxy](https://docs.gitea.com/administration/reverse-proxies) и
[обновление](https://docs.gitea.com/installation/upgrade-from-gitea).
