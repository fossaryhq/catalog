### Один из контейнеров не становится healthy

```bash
docker compose ps
docker compose logs --tail=200 immich-server
docker compose logs --tail=100 database
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q immich-server)"
```

`immich-server` не поднимется, пока база не ответит на healthcheck. Если база
падает сразу после старта, чаще всего дело в правах на volume или в изменённом
`IMMICH_DB_PASSWORD` при уже созданной базе: пароль задаётся при инициализации и
позже переменной не меняется.

### Контейнер машинного обучения перезапускается или падает

На amd64 начиная с v3 образу нужен уровень микроархитектуры x86-64-v2:

```bash
/usr/bin/ld.so --help | grep -m1 x86-64-v2
docker compose logs --tail=100 immich-machine-learning
```

Если поддержки нет, отключите машинное обучение в Administration → Settings →
Machine Learning и уберите сервис из `compose.yaml`. Умный поиск, распознавание
лиц, дубликаты и OCR при этом работать не будут.

### Загрузка с телефона обрывается на больших видео

Ограничение ставит reverse proxy, а не Immich. В Nginx нужны
`client_max_body_size 0` и увеличенные `proxy_read_timeout` и
`proxy_send_timeout`, в Caddy — `request_body max_size`, в Traefik —
middleware `buffering` с `maxRequestBodyBytes: 0`. Все три примера в `proxy/`
уже содержат эти настройки.

### Мало места на диске, хотя снимков немного

Кроме оригиналов Immich хранит превью и перекодированные видео. Проверьте, что
занимает место:

```bash
sudo du -sh /srv/immich/library/*
docker system df -v | grep immich
```

Каталог `backups` содержит автоматические дампы базы: их глубину задают в
Administration → Settings → Backup. Кэш моделей в volume
`immich-model-cache` можно удалить — он скачается заново.

### Умный поиск ничего не находит

Проверьте, что задания выполнены: Administration → Job Queues → Smart Search.
Модель CLIP по умолчанию понимает только английские запросы. Русский поиск
требует мультиязычной модели, которую выбирают в Administration → Settings →
Machine Learning → Smart Search; после смены модели нужно перезапустить задание
Smart Search для всей библиотеки.

### После обновления сервер не стартует

Смотрите логи миграций:

```bash
docker compose logs --tail=200 immich-server | grep -i migration
```

Не запускайте предыдущий образ поверх мигрированной базы — откат делается только
восстановлением архива, снятого перед обновлением. Пропущенные мажорные версии
тоже дают ошибки миграции: обновляйтесь последовательно.

### После восстановления в ленте пустые карточки

База и файлы взяты из разных снимков. Восстановите согласованную пару архивом,
созданным `backup.sh`, и не смешивайте `database.sql.gz` из одного архива с
`library.tar.gz` из другого.

### `restore.sh` завершается ошибкой psql

Дамп нельзя накатывать на базу, с которой уже работал сервер. Скрипт удаляет
volume базы перед восстановлением; если вы восстанавливаете вручную, убедитесь,
что база пустая, а `immich-server` ни разу не запускался после её создания.
