### Paperless-ngx не становится healthy

```bash
docker compose ps
docker compose logs --tail=200 webserver database broker
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q webserver)"
```

Проверьте, что оба обязательных секрета заменены, PostgreSQL и Valkey healthy,
на диске есть место, а `curl http://127.0.0.1:8000/` возвращает redirect. Первый
запуск дольше обычного из-за миграций, индекса и установки языка OCR.

### Ошибка CSRF, неверные ссылки или redirect на другой адрес

`PAPERLESS_URL` должен точно совпадать с внешним origin: схема `https`, домен,
необязательный нестандартный порт, без завершающего `/` и без пути. После
изменения выполните `docker compose up -d --force-recreate webserver`. Проверьте,
что proxy передаёт исходные `Host` и `X-Forwarded-Proto`.

### Статус обработки не обновляется

Проверьте WebSocket route и broker:

```bash
docker compose logs --tail=200 webserver broker
docker compose exec broker valkey-cli ping
```

Proxy обязан разрешать upgrade соединения для `/ws/status/`. Контейнерный proxy
не может обращаться к `127.0.0.1` хоста без host gateway.

### OCR не распознаёт язык

Переменные должны быть согласованы. `PAPERLESS_OCR_LANGUAGES` доустанавливает
пакет tesseract при старте контейнера, а `PAPERLESS_OCR_LANGUAGE` выбирает, что
распознавать; язык, указанный только во второй, молча не сработает. Для русского
вместе с английским задайте `PAPERLESS_OCR_LANGUAGES=rus` и
`PAPERLESS_OCR_LANGUAGE=rus+eng`. В логах старта должна быть установка языковых
данных. Повторный OCR существующих документов запускайте через UI только после
backup: он расходует много CPU и может изменить архивную версию документа.

### Документ остаётся в consume или обработка падает

```bash
docker compose logs --since=30m webserver
docker system df
docker compose exec webserver document_sanity_checker
```

Проверьте формат, права volume, свободный диск и RAM. Tika/Gotenberg в рецепт не
входят: требующие их Office и email-файлы не будут обрабатываться этим стеком.

### Ошибка 502 от reverse proxy

С хоста проверьте `curl -I http://127.0.0.1:8000/`. Затем проверьте upstream,
firewall и сетевой namespace proxy. Из контейнера `127.0.0.1` указывает на сам
контейнер, а не на Paperless-ngx на хосте.
