### Stirling PDF не становится healthy

```bash
docker compose ps
docker compose logs --tail=200 stirling-pdf
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q stirling-pdf)"
curl -v http://127.0.0.1:8080/api/v1/info/status
```

Endpoint должен вернуть JSON со `status: UP`. Первый старт дольше обычного из-за
создания H2 и подготовки инструментов. Проверьте 2 ГБ RAM, свободный диск, порт
8080 и права на четыре каталога данных.

### Вход не принимает initial credentials

`SECURITY_INITIALLOGIN_*` действует только при создании первой базы. Если в
`configs` уже есть `stirling-pdf-DB-*.mv.db`, изменение `.env` не меняет
пользователя. Не удаляйте H2 с документами и настройками: восстановите известный
backup или используйте поддерживаемую upstream-процедуру сброса. Убедитесь, что
в `.env` нет `CHANGE_ME` и Compose видит значения: `docker compose config`.

### Неверный redirect, CORS или ссылки

`STIRLING_PDF_URL` должен точно совпадать с origin браузера: схема, домен и
необязательный порт, без пути и завершающего `/`. После изменения выполните
`docker compose up -d --force-recreate`. Проверьте `Host` и
`X-Forwarded-Proto` от proxy. Этот рецепт поддерживает корневой `/`, не subpath.

### Upload получает 413 или обрывается

Согласуйте `STIRLING_PDF_UPLOAD_LIMIT_MB` с `client_max_body_size` Nginx или
`request_body max_size` Caddy. Проверьте временное место и RAM: обработка может
требовать в несколько раз больше размера исходного файла. Не снимайте лимит на
публичном сервисе без resource controls.

### OCR не находит язык

Проверьте содержимое `data/tessdata` и логи. Образ может не включать нужный
traineddata в каждом варианте; добавляйте только файл из официального Tesseract
tessdata и сохраняйте его в смонтированном каталоге. Не заменяйте standard image
на другой variant без повторной проверки функций и архитектуры.

### Ошибка H2 после обновления

Не запускайте старый image поверх новой схемы и не переименовывайте
`stirling-pdf-DB-<schema-version>.mv.db`. Сохраните проблемный `configs`, верните
старый тег и полный pre-update archive через `restore.sh`. Если backup нет,
остановите контейнер и запросите upstream migration guidance.

### Reverse proxy возвращает 502

С хоста проверьте `curl http://127.0.0.1:8080/api/v1/info/status`, затем upstream,
таймауты и network namespace proxy. В контейнере `127.0.0.1` означает сам proxy,
а не Stirling PDF на хосте.
