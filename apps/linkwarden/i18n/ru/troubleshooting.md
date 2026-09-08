### Linkwarden не становится healthy

```bash
docker compose ps
docker compose logs --tail=200 linkwarden postgres meilisearch
docker inspect --format '{{json .State.Health}}' "$(docker compose ps -q linkwarden)"
curl -I http://127.0.0.1:3000/
```

Проверьте три обязательных разных секрета, состояние зависимостей, свободные RAM
и диск. `POSTGRES_PASSWORD` должен быть URL-safe, потому что входит в
`DATABASE_URL`. Не удаляйте volumes рабочей установки при диагностике.

### Redirect или вход ведёт на неверный URL

`LINKWARDEN_URL` должен точно совпадать с внешней схемой и host без завершающего
`/`. Рецепт передаёт `NEXTAUTH_URL=${LINKWARDEN_URL}/api/v1/auth` и
`BASE_URL=${LINKWARDEN_URL}`. После изменения пересоздайте Linkwarden и удалите
старые cookies. Убедитесь, что proxy передаёт исходный `Host` и
`X-Forwarded-Proto=https`.

### Регистрация всё ещё доступна

Задайте `NEXT_PUBLIC_DISABLE_REGISTRATION=true`, выполните
`docker compose up -d --force-recreate linkwarden` и проверьте страницу в
приватном окне. Простого restart недостаточно, если контейнер не был пересоздан.

### Сохранённая страница не открывается или использует основной origin

Проверьте `LINKWARDEN_USER_CONTENT_URL`, DNS, TLS и второй host в proxy. Origin
должен отличаться от основного приложения и не разделять с ним cookies. Не
обходите проблему, включая private network access либо insecure TLS.

### Не сохраняется внутренний или self-signed URL

Это ожидаемая защита: `ALLOW_PRIVATE_NETWORK_ACCESS=false` и
`ALLOW_INSECURE_TLS=false` закреплены в Compose. Не ослабляйте их для общего
instance. Для доверенного внутреннего ресурса предпочтительнее публичный валидный
HTTPS endpoint или отдельный изолированный instance с egress firewall.

### Поиск не возвращает новые закладки

```bash
docker compose logs --tail=200 meilisearch linkwarden
docker compose exec meilisearch curl --fail http://127.0.0.1:7700/health
```

Убедитесь, что `MEILI_MASTER_KEY` одинаков у обоих сервисов и volume не заполнен.
Не удаляйте индекс до полного backup. Если upstream предлагает штатную
переиндексацию для этой версии, запустите её только после сохранения PostgreSQL и
архивов.

### Ошибка 502 от reverse proxy

С хоста выполните `curl -I http://127.0.0.1:3000/`. Проверьте upstream, firewall
и namespace proxy. Из контейнера `127.0.0.1` указывает на сам proxy-контейнер, а
не Linkwarden на хосте; используйте host gateway или общую закрытую сеть.
