### За reverse proxy панель отдаёт 400: Bad Request

Home Assistant не доверяет заголовку `X-Forwarded-For`, пока это не разрешено
явно. В `configuration.yaml` нужен блок `http`:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.18.0.1
```

Адрес в `trusted_proxies` — это адрес, с которого запрос приходит в контейнер, и
он почти никогда не равен `127.0.0.1`. Для proxy на хосте это адрес шлюза сети
Docker, как в примере выше; для proxy в контейнере — его адрес в общей сети.
Берите фактическое значение из лога, а не угадывайте:

```bash
docker compose logs --tail=50 home-assistant | grep -i forwarded
```

Не расширяйте список до всей подсети: любой, кто попадёт в неё, сможет подделать
адрес клиента.

### Панель открывается, но остаётся пустой

Интерфейс получает данные по WebSocket. Если proxy не пробрасывает upgrade,
страница загружается и висит. В Nginx нужны заголовки:

```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

Caddy и Traefik делают это сами. Проверить, что дело в proxy, можно обращением
напрямую через SSH-туннель на `127.0.0.1:8123`.

### Контейнер не становится healthy

```bash
docker compose ps
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q home-assistant)"
docker compose logs --tail=100 home-assistant
```

Первый запуск занимает больше времени, чем последующие: `start_period`
healthcheck равен 120 секундам. Если контейнер перезапускается по кругу, почти
всегда виновата ошибка в `configuration.yaml`:

```bash
docker compose exec home-assistant python -m homeassistant --script check_config -c /config
```

Когда ядро не может прочитать конфигурацию, оно поднимается в recovery mode:
панель работает, но интеграций и автоматизаций нет. Это видно в поле `state`
ответа `/api/config` и в шапке интерфейса.

### Устройства не находятся автоматически

Так и должно быть: контейнер работает в изолированной сети Compose и не получает
широковещательные запросы mDNS, SSDP и DHCP, на которых построен поиск.
Добавляйте интеграции вручную и указывайте IP-адрес устройства. Если
автоматический поиск нужен, придётся перейти на `network_mode: host` — это даёт
контейнеру доступ ко всей сети хоста, и такой вариант в рецепт не включён
осознанно.

### Забыт пароль владельца

В образе есть скрипт управления учётными записями. Остановите контейнер, чтобы
не править базу под работающим сервером, и смените пароль:

```bash
docker compose stop home-assistant
docker compose run --rm home-assistant python -m homeassistant --script auth --config /config list
docker compose run --rm home-assistant python -m homeassistant --script auth --config /config change_password smoke НовыйПароль
docker compose start home-assistant
```

Перед правкой сделайте backup. Удалять файлы `.storage/auth*` не нужно: вместе с
ними исчезнут все пользователи, токены мобильных приложений и привязки к
устройствам.

### База истории занимает десятки гигабайт

По умолчанию Home Assistant хранит историю 10 дней, но при большом числе
датчиков файл `home-assistant_v2.db` всё равно растёт быстро. Ограничьте срок и
исключите шумные сущности в `configuration.yaml`:

```yaml
recorder:
  purge_keep_days: 7
  exclude:
    domains:
      - device_tracker
      - sun
```

Размер файла после правки уменьшится не сразу: место освобождает служба
`recorder.purge` с параметром `repack: true`.

### После обновления сломалась интеграция

Проверьте раздел Backward-incompatible changes в release notes своей версии:
интеграции переезжают и меняют формат настроек. Быстрое решение — вернуть
прежний тег в `.env` и выполнить `docker compose up -d`. Если старая версия не
поднимается из-за уже выполненной миграции `.storage`, восстановите архив,
созданный перед обновлением:

```bash
./restore.sh ./backups/home-assistant-YYYYMMDDTHHMMSSZ.tar.gz
```

### Автоматизации срабатывают не в то время

Проверьте оба часовых пояса: контейнерный `TZ` из `.env` и пояс самого
приложения в «Настройки» → «Система» → «Общие». Автоматизации по закату и восходу
дополнительно зависят от координат, заданных при первичной настройке.

```bash
docker compose exec home-assistant date
```
