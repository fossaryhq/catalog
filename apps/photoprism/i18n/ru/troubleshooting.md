### PhotoPrism не становится healthy

```bash
docker compose ps
docker compose logs --tail=200 photoprism mariadb
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q photoprism)"
```

Первый запуск и установка TensorFlow занимают время. Проверьте свободные RAM,
swap и диск, права на каталоги originals/storage и замену всех трёх паролей.

### Ошибка подключения к MariaDB

```bash
docker compose exec mariadb healthcheck.sh --connect --innodb_initialized
docker compose exec photoprism photoprism show config | grep -i database
```

Пароль из `.env` применяется при создании volume. Его изменение не меняет уже
созданного пользователя MariaDB: верните прежнее значение или явно смените
пароль в БД. Не удаляйте volume без проверенного dump.

### Индексация падает или контейнер перезапускается

Upstream предупреждает, что менее 4 ГБ swap и жёсткие memory limits могут вызвать
рестарты при обработке больших файлов. Проверьте `free -h`, `docker stats`, логи
и место в storage. Не запускайте повторную полную индексацию до backup.

### После запуска библиотека пуста

Убедитесь, что `PHOTOPRISM_ORIGINALS_PATH` указывает на каталог с файлами и
контейнер может их читать:

```bash
docker compose exec photoprism find /photoprism/originals -maxdepth 2 -type f | head
docker compose exec photoprism photoprism index
```

### Reverse proxy возвращает 502 или неверные ссылки

С хоста проверьте `curl http://127.0.0.1:2342/api/v1/status`. Значение
`PHOTOPRISM_SITE_URL` должно точно совпадать с внешним `https` URL и заканчиваться
слешем. Proxy в контейнере не достигает host localhost без host gateway.

### После обновления PhotoPrism не запускается

Не откатывайте только тег поверх мигрированной базы. Посмотрите логи миграций,
верните прежний Compose и `.env`, затем восстановите согласованный pre-update
архив с MariaDB dump, storage и originals.
