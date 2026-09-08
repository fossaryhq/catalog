### Первый запуск падает с «is not a valid ip or domain»

Скрипт установки проверяет `SEAFILE_SERVER_HOSTNAME` и не принимает `localhost`
и любое имя без точки. Задайте настоящее имя хоста — публичный домен или имя,
которое отдаёт локальный DNS, — затем удалите наполовину инициализированный
volume и запустите заново:

```bash
docker compose down --timeout 120
docker volume rm seafile-data seafile-database
docker compose up -d --wait --wait-timeout 900
```

Делайте это только на пустой установке: на рабочей те же команды уничтожат все
библиотеки.

### Контейнер несколько минут остаётся unhealthy

Первый запуск создаёт три базы, генерирует конфигурацию в volume и только потом
поднимает Seahub — поэтому у проверки здоровья пятиминутный start period. Не
перезапускайте, а следите за прогрессом:

```bash
docker compose logs --follow seafile
docker compose ps
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q seafile)"
```

`502` с опубликованного порта в это время нормален: nginx поднимается раньше
Seahub.

### Seahub не видит базу или кеш

```bash
docker compose logs --tail=200 db cache
docker compose exec db mariadb --user=root --password="$SEAFILE_DB_ROOT_PASSWORD" -e "SHOW DATABASES;"
```

Учётные данные записываются в `conf/seafile.conf` и `conf/seahub_settings.py`
внутри volume во время установки. Смена `SEAFILE_DB_PASSWORD` или
`SEAFILE_CACHE_PASSWORD` в `.env` эти файлы не переписывает: либо верните старое
значение, либо отредактируйте сгенерированную конфигурацию.

### Ссылки, письма или клиенты указывают на неверный адрес

`SEAFILE_SERVER_HOSTNAME` и `SEAFILE_SERVER_PROTOCOL` попадают в сгенерированную
конфигурацию при первом старте. Для переезда на другой домен отредактируйте
`conf/ccnet.conf` (`SERVICE_URL`), `conf/seahub_settings.py` (`FILE_SERVER_ROOT`,
`SERVICE_URL`) и `conf/seafile.conf` внутри volume, затем перезапустите:

```bash
docker compose exec seafile grep -R "example.com" /shared/seafile/conf
docker compose restart seafile
```

### Загрузки обрываются на определённом размере или по таймауту

Обычно виноват прокси: в примерах стоят `client_max_body_size 0`, отключённая
буферизация запроса и увеличенные таймауты, потому что блоки файлов идут через
тот же origin. `413` приходит от прокси, а `500` через несколько минут обычно
означает, что сработал таймаут во время передачи.

### Запрос к /seafhttp/ возвращает 400

Это Go-файлсервер за тем же nginx, и он отвечает только по валидному токену,
поэтому голый запрос с `400` — ожидаемое поведение. Настоящие ошибки видны в
журналах:

```bash
docker compose exec seafile tail -n 100 /shared/logs/seafile/seafile.log
docker compose exec seafile tail -n 100 /shared/logs/seahub/seahub.log
```

### Зашифрованная библиотека не открывается

Библиотеки с клиентским шифрованием расшифровываются паролем, который сервер не
хранит. Административного восстановления нет: потерянный пароль библиотеки
означает, что данные останутся зашифрованными, даже если блоки есть в резервной
копии.

### Обратный прокси отвечает 502

На хосте выполните `curl -I http://127.0.0.1:8000/accounts/login/`. Если ответ
есть, прокси смотрит не туда: внутри контейнера прокси `127.0.0.1` — это он сам,
поэтому используйте адрес host gateway или общую сеть Docker. Если ответа нет,
начните с раздела про проверку здоровья.
