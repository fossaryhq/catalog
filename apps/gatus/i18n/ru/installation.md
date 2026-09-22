### 1. Проверьте сервер

Нужен Ubuntu 22.04+ или Debian 12+ с Docker Engine и Docker Compose v2.24+.
Выделите 1 ядро, 128 МБ RAM и 1 ГБ локального диска; 256 МБ RAM оставят запас
для новых проверок и истории. Рецепт использует SQLite и не требует отдельной БД.

```bash
docker --version
docker compose version
```

### 2. Подготовьте файлы и переменные

Положите `compose.yaml`, `.env.example`, `config/`, `backup.sh`, `restore.sh` и
`proxy/` в отдельный каталог:

```bash
mkdir -p ~/services/gatus
cd ~/services/gatus
cp .env.example .env
chmod 600 .env
```

В `.env` лежат закреплённая `GATUS_VERSION`, локальный `GATUS_PORT`, имя Docker
volume, `GATUS_CONFIG_DIR` и данные для входа. Оставьте каталог конфигурации
равным `./config`, если backup не должен читать его в другом месте. Замените
`change-me`. Gatus хранит bcrypt-хеш, а не пароль; эти команды создадут пароль и Base64-хеш для
`GATUS_PASSWORD_BCRYPT_BASE64`:

```bash
password="$(openssl rand -base64 32)"
printf 'Password: %s\n' "$password"
htpasswd -bnBC 9 "" "$password" | tr -d ':\n' | base64 -w0
printf '\n'
```

В Ubuntu и Debian `htpasswd` входит в пакет `apache2-utils`. Сохраните показанный
пароль в менеджере паролей: восстановить его из хеша в `.env` нельзя.

Цели находятся в `config/config.yaml`. Встроенная самопроверка доказывает работу
расписания, условий, SQLite и панели до добавления ваших сервисов. Секреты
провайдеров уведомлений храните в `.env`, передавайте через `compose.yaml` и
ссылайтесь на имена переменных из конфигурации вместо записи токенов в YAML.

### 3. Запустите контейнер на VPS

<!-- coverage:deployment-vps -->

```bash
docker compose pull
docker compose up -d
docker compose ps
curl http://127.0.0.1:8080/health
```

Последняя команда должна вывести `{"status":"UP"}`. В образе нет Docker
healthcheck, поэтому после запуска проверьте и `/health`, и завершённый результат
проверки на панели.

### 4. Откройте панель и добавьте проверки

До настройки reverse proxy используйте SSH-туннель:

```bash
ssh -L 8080:127.0.0.1:8080 user@server.example
```

Откройте `http://localhost:8080`, войдите с данными из `.env`, дождитесь зелёной
**Gatus health** и откройте её условия.

Добавьте цель в `config/config.yaml`, например:

```yaml
  - name: Public website
    group: Production
    url: https://www.example.com/
    interval: 1m
    conditions:
      - "[STATUS] == 200"
      - "[CERTIFICATE_EXPIRATION] > 48h"
      - "[RESPONSE_TIME] < 1000"
```

Выполните `docker compose restart gatus` и прочитайте логи. Начните с HTTP-
статуса, сертификата и мягкого ограничения времени ответа; ужесточайте его после
наблюдения за обычными значениями. Зелёная HTTP-проверка доказывает только этот
запрос, а не работу всех функций целевого приложения.

### Локальная сеть

<!-- coverage:deployment-lan -->

Сохраните localhost-bind и используйте SSH-туннель. Если панель нужна в доверенной
LAN, замените `127.0.0.1` в `compose.yaml` на LAN-адрес сервера, например
`192.168.1.10`, и закройте порт 8080 на внешнем интерфейсе. Не используйте
`0.0.0.0` только ради удобства.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Примеры в `proxy/` направляют `status.example.com` на локальный порт. Замените
домен своим. Caddy получит сертификат автоматически, Nginx ожидает файлы Certbot,
а Traefik использует resolver `letsencrypt`. Если Traefik запущен в контейнере,
замените `127.0.0.1` на адрес host gateway, доступный из него.

Basic Auth остаётся включённым за proxy. Gatus поддерживает OIDC, но перенос
входа в identity provider требует client secret и осознанной правки блока
`security`; не включайте оба режима случайно.

### Резервная копия

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh
./backup.sh
```

Скрипт останавливает Gatus, чтобы база SQLite, WAL и shared-memory файлы
образовали согласованный набор, затем архивирует volume вместе с `config/` и
снова запускает контейнер. Храните зашифрованную копию вне сервера: архив
содержит адреса проверок и может содержать настройки уведомлений.

### Восстановление

<!-- coverage:restore -->

Восстановление заменяет и базу, и конфигурацию:

```bash
./restore.sh ./backups/gatus-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
```

Скрипт проверяет архив и сначала снимает страховочную копию текущего состояния.
После запуска проверьте `/health`, войдите и убедитесь, что вернулись ожидаемые
цели, история и объявления.

### Обновление

<!-- coverage:update -->

Сделайте backup, прочитайте release notes, замените `GATUS_VERSION` в `.env` и
пересоздайте контейнер:

```bash
docker compose pull
docker compose up -d
docker compose logs --tail=100 gatus
```

Проверьте `/health` и дождитесь свежего результата каждой цели. Gatus применяет
изменения схемы SQLite при старте; один HTTP-ответ не доказывает, что прежняя
история читается.

### Откат

<!-- coverage:rollback -->

Верните прежнюю `GATUS_VERSION` в `.env` и выполните `docker compose pull &&
docker compose up -d`. Если старый образ не читает изменённую новой версией БД,
оставьте прежнюю версию выбранной и восстановите архив до обновления.

### Полное удаление

<!-- coverage:removal -->

`docker compose down` останавливает Gatus и сохраняет БД. Для полного удаления:

```bash
docker compose down
docker volume rm gatus-data
rm -rf ~/services/gatus
```

Источники: [официальный запуск в Docker](https://github.com/TwiN/gatus/blob/v5.36.0/README.md#docker),
[справочник конфигурации](https://github.com/TwiN/gatus/blob/v5.36.0/README.md#configuration),
[хранилище](https://github.com/TwiN/gatus/blob/v5.36.0/README.md#storage) и
[безопасность](https://github.com/TwiN/gatus/blob/v5.36.0/README.md#security).
