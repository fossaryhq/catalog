## 1. Проверьте сервер

Нужны Ubuntu 22.04+ или Debian 12+, Docker Engine и Docker Compose v2.24+.
Минимум для Node-RED — 1 CPU, 256 МБ RAM и 2 ГБ диска; для потоков с большим
числом узлов или контекстом оставьте 512 МБ. Отдельная БД не нужна: потоки,
установленные узлы и учётные данные лежат в Docker-томе.

```bash
docker --version
docker compose version
```

## 2. Подготовьте рецепт

Поместите все файлы рецепта, включая `config/settings.js`, в закрытый каталог:

```bash
mkdir -p ~/services/node-red
cd ~/services/node-red
cp .env.example .env
chmod 600 .env
```

Создайте bcrypt-хеш пароля редактора и секрет шифрования учётных данных. В
`.env` записывайте хеш, а не открытый пароль; пароль и секрет храните в менеджере
паролей. Не меняйте `NODE_RED_CREDENTIAL_SECRET` после создания credentials:
старые значения перестанут расшифровываться.

```bash
docker run --rm -it nodered/node-red:5.0.7-24 node-red admin hash-pw
openssl rand -hex 32
```

Первый вывод запишите в `NODE_RED_ADMIN_PASSWORD_HASH`, задайте нестандартный
`NODE_RED_ADMIN_USERNAME`, второй — в `NODE_RED_CREDENTIAL_SECRET`.
`NODE_RED_SETTINGS_FILE` указывает на приложенный файл JavaScript, включающий
вход по паролю; контейнер должен иметь возможность его читать.

## 3. Запустите Node-RED

<!-- coverage:deployment-vps -->

```bash
docker compose pull
docker compose up -d
docker compose ps
curl -I http://127.0.0.1:1880/
```

Последняя команда возвращает HTTP-ответ, но редактор должен запросить заданные
выше credentials. Для первого входа используйте SSH-туннель:

```bash
ssh -L 1880:127.0.0.1:1880 user@server.example
```

Откройте `http://localhost:1880`, войдите, перетащите на новый поток узлы
**Inject** и **Debug**, соедините их и нажмите **Deploy**. Так вы проверите, что
редактор сохраняет и исполняет поток. Не помещайте настоящие токены в
незашифрованный export или скриншоты.

## Локальная сеть

<!-- coverage:deployment-lan -->

По возможности сохраните localhost bind и SSH-туннель. Для доверенной LAN
замените `127.0.0.1` в пробросе порта на LAN-IP сервера, например
`192.168.1.10`, и закройте порт 1880 со всех прочих сетей. Не открывайте порт
на все интерфейсы: пароль не заменяет TLS и сетевой контроль доступа.

## Домен и HTTPS

<!-- coverage:deployment-domain-https -->

В `proxy/` есть примеры Caddy, Nginx и Traefik для `flows.example.com`. Замените
имя своим. Caddy получает TLS автоматически, Nginx ожидает сертификаты Certbot,
Traefik использует resolver `letsencrypt`. При адаптации сохраняйте заголовки
`Host`, `X-Forwarded-For` и `X-Forwarded-Proto`. До публикации webhook войдите
через HTTPS-адрес.

## Резервная копия

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт ненадолго останавливает Node-RED и архивирует весь том данных: потоки,
установленные модули палитры и зашифрованные credentials. Храните копию вне
сервера в зашифрованном виде; секрет из `.env` и `config/settings.js` держите
вместе с ней, но защищайте отдельно.

## Восстановление

<!-- coverage:restore -->

Восстановление необратимо заменяет текущий том. Сначала создаётся safety backup,
затем загружается выбранный архив:

```bash
./restore.sh ./backups/node-red-YYYYMMDDTHHMMSSZ.tar.gz
docker compose up -d
```

Откройте редактор и задеплойте безопасный сохранённый поток. Используйте
`NODE_RED_CREDENTIAL_SECRET` на момент создания архива: без него credentials не
будут работать.

## Обновление

<!-- coverage:update -->

Сначала сделайте backup, прочитайте [release notes](https://github.com/node-red/node-red/releases),
поменяйте `NODE_RED_VERSION` в `.env` и пересоздайте сервис:

```bash
docker compose pull
docker compose up -d
docker compose logs --tail=100 node-red
```

Войдите и задеплойте небольшой существующий flow. До смены варианта Node.js
(`-24`) или сторонних узлов изучите примечания к релизу.

## Откат

<!-- coverage:rollback -->

Верните прежний image tag в `.env` и пересоздайте контейнер. Если старая версия
не читает данные после обновления, восстановите backup, созданный до него:

```bash
docker compose up -d
./restore.sh ./backups/node-red-PRE-UPDATE.tar.gz
```

## Полное удаление

<!-- coverage:removal -->

`docker compose down` останавливает сервис, но сохраняет потоки. После проверки
внешней копии удалить всё можно так:

```bash
docker compose down
docker volume rm node-red-data
rm -rf ~/services/node-red
```

Источники: [официальный Docker guide](https://nodered.org/docs/getting-started/docker),
[защита редактора](https://nodered.org/docs/user-guide/runtime/securing-node-red)
и [projects с файлами потоков](https://nodered.org/docs/user-guide/projects/).
