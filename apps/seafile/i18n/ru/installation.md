### 1. Проверьте сервер на Ubuntu или Debian

Подойдёт Ubuntu 22.04+ или Debian 12+ с Docker Engine и Compose v2.24+. Upstream
просит минимум 2 ядра и 2 ГБ RAM; закладывайте 4 ГБ и диск под все библиотеки
плюс историю версий, которую каждая библиотека хранит. Публикуемый образ есть
только для amd64, поэтому ARM-плата для этого рецепта не поддерживается.

```bash
docker --version
docker compose version
```

### 2. Подготовьте рецепт и четыре независимых секрета

```bash
mkdir -p ~/services/seafile
cd ~/services/seafile
cp .env.example .env
chmod 600 .env
admin_password="$(openssl rand -hex 24)"
db_root_password="$(openssl rand -hex 32)"
db_password="$(openssl rand -hex 32)"
jwt_key="$(openssl rand -hex 32)"
cache_password="$(openssl rand -hex 32)"
sed -i "s|^SEAFILE_ADMIN_PASSWORD=.*|SEAFILE_ADMIN_PASSWORD=$admin_password|" .env
sed -i "s|^SEAFILE_DB_ROOT_PASSWORD=.*|SEAFILE_DB_ROOT_PASSWORD=$db_root_password|" .env
sed -i "s|^SEAFILE_DB_PASSWORD=.*|SEAFILE_DB_PASSWORD=$db_password|" .env
sed -i "s|^SEAFILE_JWT_PRIVATE_KEY=.*|SEAFILE_JWT_PRIVATE_KEY=$jwt_key|" .env
sed -i "s|^SEAFILE_CACHE_PASSWORD=.*|SEAFILE_CACHE_PASSWORD=$cache_password|" .env
echo "пароль администратора: $admin_password"
unset admin_password db_root_password db_password jwt_key cache_password
```

Ключ JWT должен быть не короче 32 символов. Все пять значений должны различаться
и оставаться неизменными: сервер сохраняет сгенерированную конфигурацию внутри
volume и ждёт тех же учётных данных базы и кеша при каждом старте.

Публичное имя задайте до первого запуска:

```bash
sed -i "s|^SEAFILE_SERVER_HOSTNAME=.*|SEAFILE_SERVER_HOSTNAME=files.example.com|" .env
sed -i "s|^SEAFILE_ADMIN_EMAIL=.*|SEAFILE_ADMIN_EMAIL=you@example.com|" .env
```

Все переменные `.env`:

- `SEAFILE_PORT` — локальный web-порт, по умолчанию `8000`;
- `SEAFILE_SERVER_HOSTNAME` — внешнее имя хоста без схемы и слеша; скрипт установки не принимает `localhost`;
- `SEAFILE_SERVER_PROTOCOL` — схема, по которой сервис доступен снаружи; за примерами прокси это `https`;
- `SEAFILE_ADMIN_EMAIL` и `SEAFILE_ADMIN_PASSWORD` создают первую учётную запись только при первом старте;
- `SEAFILE_DB_ROOT_PASSWORD` — пароль root в MariaDB, нужен для установки и дампов;
- `SEAFILE_DB_PASSWORD` — пароль роли `seafile`;
- `SEAFILE_JWT_PRIVATE_KEY` подписывает внутренние служебные токены, не короче 32 символов;
- `SEAFILE_CACHE_PASSWORD` защищает кеш Valkey, который наружу не публикуется;
- `SEAFILE_DB_USER` — имя роли базы, меняется только до первого запуска;
- `SEAFILE_TIME_ZONE` — часовой пояс IANA;
- `SEAFILE_DATA_VOLUME` и `SEAFILE_DB_VOLUME` — имена volume с хранилищем объектов и базой;
- `SEAFILE_BACKUP_DIR` — каталог резервных копий на хосте.

### 3. Запустите и войдите

```bash
docker compose config
docker compose pull
docker compose up -d --wait --wait-timeout 900
docker compose ps
curl --fail --silent --output /dev/null http://127.0.0.1:8000/accounts/login/
```

Первый запуск долгий: контейнер создаёт `ccnet_db`, `seafile_db` и `seahub_db`,
генерирует конфигурацию в volume и только потом поднимает Seahub за собственным
nginx. Войдите по внешнему адресу под `SEAFILE_ADMIN_EMAIL`, затем поставьте
настольный или мобильный клиент и подключите его к тому же адресу.

### Развёртывание на VPS

<!-- coverage:deployment-vps -->

Оставьте `127.0.0.1:${SEAFILE_PORT}:80`: до сервера доберётся только
HTTPS-прокси на этом же хосте. У MariaDB и кеша опубликованных портов нет. В
файрволе откройте SSH, HTTP и HTTPS. Задайте `SEAFILE_SERVER_PROTOCOL=https` и
создайте DNS-запись до первого старта: значение попадает в сгенерированную
конфигурацию, а клиенты, настроенные с неверной схемой, продолжат её
использовать.

### Доступ из доверенной локальной сети

<!-- coverage:deployment-lan -->

Лучше `ssh -L 8000:127.0.0.1:8000 user@server`. Постоянной установке в локальной
сети нужно разрешимое имя хоста — `localhost` скрипт установки не принимает,
поэтому возьмите имя, которое отдаёт ваш локальный DNS, задайте
`SEAFILE_SERVER_PROTOCOL=http`, замените привязку к localhost одним конкретным
приватным IP и ограничьте порт файрволом. Зашифрованные на клиенте библиотеки
останутся защищёнными, но всё остальное, включая сессионные cookie, пойдёт по
такому маршруту открытым текстом.

### Домен, HTTPS и загрузки

<!-- coverage:deployment-domain-https -->

Задайте `SEAFILE_SERVER_HOSTNAME=files.example.com` и
`SEAFILE_SERVER_PROTOCOL=https`, затем замените хост в примере для Caddy, Nginx
или Traefik. Прокси не должен ограничивать тело запроса — блоки файлов идут
через тот же origin, поэтому в примере для Nginx стоят `client_max_body_size 0`
и отключённая буферизация запроса — и должен допускать долгие передачи, так что
таймауты чтения и отправки держите большими. Смена имени хоста после первого
старта требует правки `conf/ccnet.conf`, `conf/seahub_settings.py` и
`conf/seafile.conf` внутри volume.

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает Seafile, снимает дамп всех трёх баз через `mariadb-dump`,
архивирует весь volume `/shared` с хранилищем объектов и складывает рядом `.env`
и `compose.yaml`. Нужны обе половины: дамп базы без блоков восстановит индекс,
который ссылается на несуществующие файлы. В архиве все файлы и все секреты —
шифруйте его и увозите за пределы сервера.

### Восстановление

<!-- coverage:restore -->

Восстановление необратимо заменяет хранилище объектов и все три базы.
Используйте те же версии Seafile и MariaDB и текущий `.env`:

```bash
./restore.sh ./backups/seafile-YYYYMMDDTHHMMSSZ.tar
curl --fail --silent --output /dev/null http://127.0.0.1:8000/accounts/login/
```

Скрипт сначала делает резервную копию заменяемого состояния, пересоздаёт оба
volume, распаковывает хранилище, импортирует дамп и поднимает сервер. Настольные
клиенты, синхронизировавшиеся после резервной копии, зальют свои локальные
изменения заново: проверьте один клиент, прежде чем подключать остальные.
Практическую проверку восстановления процедура не проходила — отрепетируйте её
на отдельном сервере.

### Обновление Seafile

<!-- coverage:update -->

Сначала резервная копия и upstream-заметки к конкретной паре версий. Обновление
внутри одной мажорной серии — это смена тега:

```bash
./backup.sh
docker compose pull
docker compose up -d --wait --wait-timeout 900
docker compose logs --tail=200 seafile
```

Мажорное обновление устроено иначе: Seafile выполняет версионные скрипты
обновления и требует переходить по одной мажорной версии за раз, начиная с
последней минорной текущей серии. Не прыгайте с 12.x на 14.x и не меняйте
MariaDB тем же шагом. Точный тег `seafileltd/seafile-mc:13.0.25` заменяйте на
проверенную версию, никогда на `-latest` или `-testing`.

### Откат

<!-- coverage:rollback -->

Никогда не запускайте старый Seafile поверх баз, которые уже обновила новая
версия. Верните предыдущий точный тег вместе с архивом, сделанным до обновления:

```bash
docker compose down --timeout 120
./restore.sh ./backups/seafile-BEFORE-UPDATE.tar
```

После неудачной смены MariaDB подключайте старый образ только к сохранённому
старому volume либо импортируйте совместимый дамп в пустой volume.

### Остановка и удаление

<!-- coverage:removal -->

`docker compose down` сохраняет оба volume. После проверки резервной копии за
пределами сервера удалите всё безвозвратно:

```bash
docker compose down
docker volume rm seafile-data seafile-database
rm -rf ~/services/seafile
```

Если имена volume изменены, подставьте фактические. Настольные клиенты держат
свои локальные копии всех синхронизированных библиотек — если данные должны
исчезнуть везде, удалите их отдельно.

Источники: [Seafile CE в Docker](https://manual.seafile.com/13.0/setup/setup_ce_by_docker/),
[compose-файл upstream](https://manual.seafile.com/13.0/repo/docker/ce/seafile-server.yml),
[резервное копирование и восстановление](https://manual.seafile.com/13.0/administration/backup_recovery/) и
[аутентификация через OAuth](https://manual.seafile.com/13.0/config/oauth/).
