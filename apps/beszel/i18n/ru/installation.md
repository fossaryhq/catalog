<!-- coverage:os -->
## Установка
Нужны Ubuntu 24.04 LTS или Debian 12/13, Docker Engine и Compose >=2.24.0 из [официального репозитория](https://docs.docker.com/engine/install/). Скачайте рецепт целиком.

```bash
cp .env.example .env
chmod 600 .env
openssl rand -hex 24
```
Замените CHANGE_ME в `BESZEL_ADMIN_PASSWORD` случайным значением, укажите свой `BESZEL_ADMIN_EMAIL` и реальный `BESZEL_URL`.

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait
docker compose ps
```
Откройте `http://localhost:8090` и войдите с заданными email/паролем. На новой базе они создают администратора Beszel и суперпользователя PocketBase; при существующей базе окружение не меняет пароли. Не открывайте панель до настройки закрытых credentials.

<!-- coverage:deployment-vps -->
## VPS
Нужны домен, HTTPS, firewall и зашифрованные внешние копии. Оставьте 8090 на loopback и публикуйте только прокси. Доступ к /_/ ограничьте доверенными операторами.

<!-- coverage:deployment-lan -->
## LAN / VPN
Предпочтительны SSH-туннель (`ssh -L 8090:127.0.0.1:8090 user@server`) или VPN/прокси. Для прямой доверенной LAN явно поменяйте bind в Compose и ограничьте firewall. BESZEL_URL должен совпадать с адресом браузера.

<!-- coverage:deployment-domain-https -->
## HTTPS
Направьте DNS на прокси, задайте BESZEL_URL=https://metrics.example.com и пересоздайте сервис. Пропускайте WebSocket upgrade и долгие соединения: они нужны live-интерфейсу и WebSocket-агентам.

<!-- coverage:proxy-caddy -->
## Caddy
Используйте proxy/Caddyfile на хосте; Caddy обслуживает TLS и WebSocket.

<!-- coverage:proxy-nginx -->
## Nginx
Получите указанный сертификат, подключите proxy/nginx.conf в контексте http, проверьте nginx -t и перезагрузите. map выбирает правильный заголовок Connection.

<!-- coverage:proxy-traefik -->
## Traefik
Загрузите proxy/traefik.yaml через file provider с websecure и resolver letsencrypt. Пример рассчитан на Traefik хоста; контейнеру нужен маршрут к панели вместо loopback хоста.

<!-- coverage:data -->
## Data / Данные
Именованный BESZEL_DATA_VOLUME подключён к /beszel_data: data.db, auxiliary.db, закрытый id_ed25519, состояние уведомлений и встроенные backup. Сохраняйте весь каталог, включая WAL работающего сервиса. Данных агентов здесь нет. Смена имени тома выбирает другую установку.

<!-- coverage:backup -->
## Backup
Выполните bash backup.sh. Скрипт останавливает панель, сохраняет весь том, .env и Compose и возвращает прежнее состояние запуска. Права архива — 600. Шифруйте и выносите копии с сервера; конфигурацию, токен и данные каждого агента храните отдельно.

<!-- coverage:restore -->
## Restore / Восстановление
Восстановление заменяет текущие данные. Используйте доверенный архив. На новой машине сначала запустите рецепт, вручную сравните архивную configuration.env (она не активируется) и выполните bash restore.sh /safe/path/beszel-backup.tar. Скрипт проверяет обязательные файлы, делает страховочную копию, заменяет данные и ждёт health. При ошибке распаковки панель остаётся остановленной. Используются пароли и SSH-ключ восстановленной базы; проверьте историю и переподключение агентов.

<!-- coverage:update -->
## Update / Обновление
Прочитайте release notes, сделайте backup, установите новый явный BESZEL_VERSION и выполните docker compose pull && docker compose up -d --wait. Не используйте latest. Отдельно обновляйте агентов до совместимой фиксированной версии и проверяйте метрики. Обновление панели — замена образа на месте; перед будущими major-релизами изучайте инструкции миграции.

<!-- coverage:rollback -->
## Rollback / Откат
Остановите beszel, верните прежний BESZEL_VERSION в .env, скачайте и один раз запустите его, затем восстановите соответствующий архив до обновления. База после миграций нового PocketBase/Beszel может не работать со старым бинарником: возвращайте старый снимок. Проверьте вход, назначенные системы и соединения агентов.

<!-- coverage:removal -->
## Removal / Удаление
docker compose down сохраняет том. Для полного удаления сначала выгрузите backup, проверьте проект и BESZEL_DATA_VOLUME, затем выполните docker compose down --volumes. Аккаунты, SSH-ключ и история будут уничтожены. .env, DNS/прокси и отдельные агенты удаляйте, когда они больше не нужны.

## Все параметры .env.example

| Variable | Назначение |
| --- | --- |
| `BESZEL_VERSION` | Тег панели 0.21.1 |
| `BESZEL_PORT` | HTTP-порт loopback хоста, исходно8090 |
| `BESZEL_URL` | Реальный внешний URL интерфейса и ссылок |
| `BESZEL_ADMIN_EMAIL` | Email начального администратора/суперпользователя, только новая БД |
| `BESZEL_ADMIN_PASSWORD` | Случайный начальный пароль; замените CHANGE_ME |
| `BESZEL_DATA_VOLUME` | Уникальное имя постоянного тома |
| `TZ` | Часовой пояс IANA, исходно Etc/UTC |
| `BESZEL_BACKUP_DIR` | Необязательная закрытая папка архивов |

## Подключение реальных систем
Через Add System создайте запись и используйте инструкции [агента](https://beszel.dev/guide/agent-installation) для нужной машины. Замените плавающий тег в предложенной UI-команде на `henrygd/beszel-agent:0.21.1`. Для SSH разрешайте порт агента только панели; для WebSocket используйте TLS. Не копируйте Docker socket, host network или устройства без необходимости: они расширяют доступ. Публичный ключ панели — не закрытый ключ. SMTP, OIDC, MFA и доставка оповещений в рецепте не настроены.
