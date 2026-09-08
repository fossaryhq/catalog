### 1. Проверьте сервер Ubuntu или Debian

Нужны Ubuntu 22.04+ или Debian 12+, Docker Engine и Compose v2.24+. Выделите
минимум 2 CPU, 2 ГБ RAM и 10 ГБ диска; рекомендуется 4 ГБ RAM. OCR, LibreOffice
и обработка больших PDF кратковременно используют больше CPU, RAM и временного
места.

```bash
docker --version
docker compose version
```

### 2. Подготовьте рецепт и обязательные учётные данные

```bash
mkdir -p ~/services/stirling-pdf
cd ~/services/stirling-pdf
cp .env.example .env
chmod 600 .env
mkdir -p data/{configs,customFiles,pipeline,tessdata}
sed -i "s|^STIRLING_PDF_INITIAL_PASSWORD=.*|STIRLING_PDF_INITIAL_PASSWORD=$(openssl rand -base64 36 | tr -d '\n')|" .env
```

До **первого** запуска замените `STIRLING_PDF_INITIAL_USERNAME` на своё имя и
сохраните сгенерированный пароль в менеджере секретов. Переменные initial login
используются только при создании H2; изменение `.env` позже не сбрасывает пароль.
Значение по умолчанию `admin/stirling` этим рецептом не используется.

Все переменные `.env`:

- `STIRLING_PDF_PORT` — локальный web-порт, обычно `8080`;
- `STIRLING_PDF_URL` — точный внешний origin со схемой, без завершающего `/` и пути; он передаётся как frontend URL, backend URL и единственный CORS origin;
- `STIRLING_PDF_DATA_PATH` — корень четырёх bind-каталогов;
- `STIRLING_PDF_INITIAL_USERNAME` и `STIRLING_PDF_INITIAL_PASSWORD` — обязательные нестандартные данные первого администратора;
- `STIRLING_PDF_DEFAULT_LOCALE` — locale интерфейса, по умолчанию `en-GB`; `ru-RU` и другие поддерживаемые локали тоже работают;
- `STIRLING_PDF_UPLOAD_LIMIT_MB` — защитный лимит файла и запроса от 1 до 999 МБ;
- `STIRLING_PDF_BACKUP_DIR` — каталог архивов на хосте.

`configs` хранит настройки, пользователей и файл H2
`stirling-pdf-DB-<schema-version>.mv.db`; `customFiles` — оформление и подписи;
`pipeline` — автоматизации и watched folders; `tessdata` — OCR-языки. Логи
читайте через `docker compose logs`: отдельный постоянный `/logs` не нужен для
восстановления и намеренно не включён.

### 3. Запустите и смените пароль

```bash
docker compose config
docker compose pull
docker compose up -d --wait
curl --fail http://127.0.0.1:8080/api/v1/info/status
```

Откройте `STIRLING_PDF_URL`, войдите с initial credentials и сразу смените
пароль в настройках учётной записи. Авторизация включена. Analytics, PostHog,
Scarf, Google visibility и URL-to-PDF выключены; health endpoint остаётся
доступным без входа. Не публикуйте сервис до проверки входа.

### Запуск на VPS

<!-- coverage:deployment-vps -->

Оставьте `127.0.0.1:${STIRLING_PDF_PORT}:8080`, откройте в firewall только SSH,
HTTP и HTTPS и публикуйте приложение через proxy на том же хосте. До первого
старта задайте реальный HTTPS origin в `STIRLING_PDF_URL`, DNS и proxy. H2
подходит этому бесплатному одноконтейнерному рецепту; внешний PostgreSQL не
добавляйте как «улучшение», пока нет подходящей платной лицензии.

### Доступ в доверенной локальной сети

<!-- coverage:deployment-lan -->

Предпочтителен VPN или туннель
`ssh -L 8080:127.0.0.1:8080 user@server`. Для него временно задайте
`STIRLING_PDF_URL=http://localhost:8080`. Для постоянного LAN-доступа замените
только `127.0.0.1` в Compose на конкретный приватный адрес, задайте совпадающий
origin и ограничьте порт firewall. Не используйте `0.0.0.0` без фильтрации.

### Домен и HTTPS

<!-- coverage:deployment-domain-https -->

Задайте `STIRLING_PDF_URL=https://pdf.example.com` без пути и завершающего слеша,
замените домен в `proxy/Caddyfile`, `proxy/nginx.conf` или
`proxy/traefik.yaml`, затем пересоздайте контейнер. Caddy получает сертификат
автоматически, Nginx ожидает Certbot, Traefik использует resolver `letsencrypt`.
Proxy должен сохранять `Host`, `X-Forwarded-Proto` и клиентский адрес, а его
upload limit должен совпадать с `STIRLING_PDF_UPLOAD_LIMIT_MB`. Контейнерный
proxy не видит localhost хоста: используйте доступный host gateway или общую
Docker network.

### Резервное копирование

<!-- coverage:backup -->

```bash
chmod +x backup.sh restore.sh smoke-test.sh
./backup.sh
```

Скрипт останавливает Stirling PDF, чтобы H2 не менялась во время копирования,
вместе архивирует `configs`, `customFiles`, `pipeline` и `tessdata`, затем снова
запускает контейнер. Архив содержит H2 с пользователями и чувствительными
настройками: зашифруйте его, скопируйте за пределы сервера и регулярно проверяйте
restore. Входные и временные PDF обычно удаляются приложением и в backup не
входят; отдельные разрешённые pipeline-каталоги вне `STIRLING_PDF_DATA_PATH`
нужно копировать отдельно.

### Восстановление

<!-- coverage:restore -->

Restore необратимо заменяет все четыре каталога. Верните в Compose **ту же
версию 2.14.3**, оставьте активный `.env`, проверьте место и выполните:

```bash
./restore.sh ./backups/stirling-pdf-YYYYMMDDTHHMMSSZ.tar.gz
docker compose ps
curl --fail http://127.0.0.1:8080/api/v1/info/status
```

Скрипт сохраняет заменяемое состояние в emergency archive, восстанавливает
остановленный снимок и ждёт healthcheck. Процедура имеет
`restore_tested: false`: сначала испытайте копию на отдельном сервере и проверьте
вход, настройки, custom files и pipeline.

### Обновление

<!-- coverage:update -->

Сделайте backup, прочитайте release notes, migration guide и лицензию новой
версии. Замените только точный тег `stirlingtools/stirling-pdf:2.14.3` на
проверенный semantic version, никогда не используйте `latest`, затем:

```bash
docker compose pull
docker compose up -d --wait
docker compose logs --tail=200 stirling-pdf
curl --fail http://127.0.0.1:8080/api/v1/info/status
```

Startup может мигрировать схему H2 и создать файл с новым schema version.
Отдельно проверяйте major-релизы, изменения persistent paths и User License.

### Откат

<!-- coverage:rollback -->

Не запускайте старый образ поверх уже мигрированной H2. Остановите контейнер,
верните прежний точный тег и восстановите полный **pre-update** архив через
`restore.sh`. H2 не имеет поддерживаемого downgrade: откат миграции означает
возврат согласованного `configs` вместе с `customFiles`, `pipeline` и `tessdata`.
Если backup отсутствует, сохраните текущее состояние и обращайтесь к upstream,
не переименовывайте файлы H2 вручную.

### Остановка и полное удаление

<!-- coverage:removal -->

`docker compose down` сохраняет bind-каталоги. После проверки внешнего backup
удалить всё безвозвратно:

```bash
docker compose down
rm -rf ./data ./backups .env
```

Источники: [Docker installation](https://docs.stirlingpdf.com/Installation/Docker%20Install/),
[configuration](https://docs.stirlingpdf.com/Configuration/),
[production, health и backup](https://docs.stirlingpdf.com/Production-Deployment-Guide/),
[analytics](https://docs.stirlingpdf.com/analytics-telemetry/),
[modes and licensing](https://docs.stirlingpdf.com/Modes%20and%20Licensing/) и
[лицензия 2.14.3](https://github.com/Stirling-Tools/Stirling-PDF/blob/v2.14.3/LICENSE).
