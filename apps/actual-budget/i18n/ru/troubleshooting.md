### Контейнер не становится healthy

```bash
docker compose ps
docker compose logs --tail=200 actual
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q actual)"
```

Проверка здоровья запускает внутри контейнера `node scripts/health-check.js`,
который обращается к `/health`. Если контейнер стартовал, но проверку не
проходит, почти всегда дело в правах на volume или в значении
`ACTUAL_LOGIN_METHOD`, отличном от `password`, `openid` и `header`.

### Экран первичной настройки снова просит пароль

`/account/needs-bootstrap` показывает, задан ли пароль:

```bash
curl --fail http://127.0.0.1:5006/account/needs-bootstrap
```

`"bootstrapped":false` на уже настроенном инстансе означает, что сервер смотрит
в пустой `server-files` — обычно из-за переименованного или пересозданного
volume. Прежде чем задавать новый пароль, проверьте `ACTUAL_DATA_VOLUME` и
`docker volume ls`: бюджет остался в старом volume.

### Пароль сервера потерян

Команды сброса нет. Остановите сервер, удалите `account.sqlite` из
`server-files` и пройдите первичную настройку заново — файлы бюджета в
`user-files` сохранятся:

```bash
docker compose stop actual
docker run --rm -v actual-data:/data alpine:3.22 rm -f /data/server-files/account.sqlite
docker compose start actual
```

Сначала сделайте резервную копию. Если для бюджета включено сквозное шифрование,
его пароль — отдельный и таким способом не восстанавливается.

### Клиент не синхронизируется или сообщает о конфликте

У каждого клиента полная локальная копия, поэтому восстановленный из архива
сервер отстаёт от клиентов. Откройте бюджет в клиенте и выполните «Reset sync» в
настройках файла либо удалите локальный файл и скачайте бюджет с сервера заново.
Делайте это по одному устройству за раз, иначе два клиента зальют расходящиеся
копии.

### Синхронизация падает на большом бюджете

Ограничения заданы явно: `ACTUAL_UPLOAD_FILE_SYNC_SIZE_LIMIT_MB`,
`ACTUAL_UPLOAD_SYNC_ENCRYPTED_FILE_SYNC_SIZE_LIMIT_MB` и
`ACTUAL_UPLOAD_FILE_SIZE_LIMIT_MB`. Поднимайте их вместе с лимитом тела запроса
на прокси — в примере для Nginx это `client_max_body_size` — и пересоздавайте
контейнер.

### Банковская синхронизация ничего не делает

GoCardless и SimpleFIN настраиваются внутри приложения, а не в рецепте, и обоим
нужен исходящий HTTPS из контейнера. Посмотрите ошибку провайдера в журнале,
затем проверьте исходящий доступ:

```bash
docker compose exec actual node -e "fetch('https://bankaccountdata.gocardless.com/api/v2/').then(r=>console.log(r.status)).catch(e=>{console.error(e.message);process.exit(1)})"
```

### Обратный прокси отвечает 502 или страница открывается, но не синхронизируется

На хосте выполните `curl -I http://127.0.0.1:5006/`. Если ответ есть, проблема в
прокси: внутри контейнера прокси `127.0.0.1` — это он сам, поэтому используйте
адрес host gateway или общую сеть Docker. Если страница грузится, но
синхронизации нет, прокси обычно режет WebSocket-апгрейды — оба примера их
пропускают.
