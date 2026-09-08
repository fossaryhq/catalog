### FreshRSS не становится healthy

```bash
docker compose ps
docker compose logs --tail=200 freshrss database
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q freshrss)"
docker compose exec freshrss cli/health.php
```

Проверьте три обязательных разных секрета, состояние PostgreSQL, свободный диск и
first-run ошибки. Пароли должны быть alphanumeric без пробелов и shell-символов.
Если пустая установка оборвалась до завершения, изучите логи и только затем
удалите пустые volumes и повторите старт; никогда не удаляйте рабочие данные.

### Неверный redirect, URL или WebSub callback

`FRESHRSS_BASE_URL` должен точно совпадать с внешним URL: схема, host,
необязательный порт и путь, без завершающего `/`. Значение применяется только при
первой установке; для существующего instance измените `base_url` в data
`config.php` по официальной инструкции, затем пересоздайте контейнер. Проще и
надёжнее использовать отдельный поддомен, а не subpath.

### API-клиент не входит

Убедитесь, что клиент использует `FRESHRSS_ADMIN_API_PASSWORD`, а не пароль web
form, и endpoint Google Reader API на том же HTTPS host. Проверьте, что Nginx
передаёт `Authorization`; Caddy и Traefik делают это по умолчанию. WebSocket
FreshRSS не нужен.

### Ленты с внутренних адресов доступны

Это поведение FreshRSS 1.29.1, а не ошибка рецепта. Не добавляйте wildcard
internal-host allowlist: такой поддерживаемой переменной в этой версии нет, а
разрешение всех адресов создало бы ложное ощущение защиты. Для недоверенных пользователей
запретите container egress к loopback, RFC1918, link-local и cloud metadata
средствами firewall/сети либо разместите FreshRSS в отдельной сети.

### После настройки proxy неверен IP клиента

Безопасный `FRESHRSS_TRUSTED_PROXY=0` отключает обработку forwarded client IP.
Если точный IP нужен, доверяйте только последнему proxy IP/CIDR и защитите
соединение до FreshRSS. Широкая сеть позволяет подделать IP и заголовки
`Remote-User`/`X-WebAuth-User`, вплоть до входа администратором.

### Расширение ломает страницу или CSP

Отключите стороннее расширение через UI либо восстановите `extensions` из
backup. Не маскируйте ошибку отключением предупреждения и не переопределяйте
`Content-Security-Policy` в reverse proxy: FreshRSS выдаёт собственную CSP.

### Ошибка 502 от reverse proxy

С хоста выполните `curl -I http://127.0.0.1:8080/`. Проверьте upstream, firewall
и namespace proxy. Из контейнера `127.0.0.1` указывает на сам proxy-контейнер, а
не на FreshRSS на хосте; используйте host gateway или общую закрытую сеть.
