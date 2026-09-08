### Сообщение «Доступ через недоверенный домен»

Nextcloud принимает запросы только с доменов из списка. Добавьте нужный в
`.env` и перезапустите:

```bash
grep NEXTCLOUD_TRUSTED_DOMAINS .env
docker compose up -d
docker compose exec -u www-data app php occ config:system:get trusted_domains
```

Переменная применяется только при старте контейнера; изменить список у
работающего инстанса можно командой
`occ config:system:set trusted_domains 1 --value=cloud.example.com`.

### Ссылки ведут на http вместо https

За reverse proxy Nextcloud не знает, что снаружи HTTPS. Заполните в `.env`
`NEXTCLOUD_TRUSTED_PROXIES`, `NEXTCLOUD_OVERWRITE_PROTOCOL=https` и
`NEXTCLOUD_OVERWRITE_CLI_URL`, затем перезапустите стек.

### Календарь и контакты не подключаются в клиентах

Клиенты обращаются к `/.well-known/caldav` и `/.well-known/carddav`. Эти адреса
должны перенаправляться на `/remote.php/dav` — примеры в `proxy/` уже содержат
нужные правила. Проверить можно так:

```bash
curl -sI https://cloud.example.com/.well-known/caldav | head -3
```

### Фоновые задания не выполняются

```bash
docker compose ps cron
docker compose exec -u www-data app php occ config:app:get core backgroundjobs_mode
docker compose logs --tail=50 cron
```

Режим должен быть `cron`. Значение записывается при первом запуске `cron.php`,
поэтому сразу после установки поле может быть пустым — контейнер `cron`
выполняет задание раз в пять минут.

### Не загружаются большие файлы

Ограничение чаще ставит reverse proxy, а не PHP. В Nginx нужен
`client_max_body_size`, в Caddy — `request_body max_size`, в Traefik —
middleware `buffering`; примеры в `proxy/` уже настроены. Со стороны PHP размер
задаёт `NEXTCLOUD_PHP_UPLOAD_LIMIT`.

### Ошибка прав на каталог данных

Внутри контейнера Nextcloud работает от UID 33:

```bash
ls -ld /srv/nextcloud/data
sudo chown -R 33:33 /srv/nextcloud/data
```

### Файлы появились на диске, но их нет в интерфейсе

Nextcloud хранит список файлов в базе и не сканирует каталог автоматически.
После ручного копирования выполните:

```bash
docker compose exec -u www-data app php occ files:scan --all
```

### Инстанс завис в режиме обслуживания

Так бывает, если обновление прервалось:

```bash
docker compose exec -u www-data app php occ maintenance:mode --off
docker compose exec -u www-data app php occ status
```

Если сервер жалуется на незавершённое обновление, сначала выполните
`occ upgrade`, а при неудаче восстановитесь из архива.

### Раздел проверок показывает предупреждения

Это нормальное состояние сразу после установки: часть проверок относится к HTTPS
и заголовкам, которые появляются только после публикации через reverse proxy.
Пройдите по списку в Administration → Overview и закрывайте пункты по одному —
там же есть ссылки на документацию по каждому.

### После обновления сервер не стартует

```bash
docker compose logs --tail=200 app | grep -i "error\|upgrade\|migration"
```

Перепрыгивать через мажорную версию нельзя: обновляйтесь последовательно.
Понижение версии не поддерживается — возврат возможен только восстановлением
архива, снятого до обновления.
