## Контейнер завершается или остаётся unhealthy

Проверьте настройки и обязательные переменные:

```bash
docker compose config
docker compose ps --all
docker compose logs --tail=200 node-red
```

`NODE_RED_ADMIN_PASSWORD_HASH` должен быть bcrypt-хешем, а не открытым паролем.
Создайте его через `node-red admin hash-pw` и пересоздайте контейнер.

## Редактор отвечает 401 или вход не работает

Убедитесь, что в `.env` есть текущий пользователь и хеш, затем пересоздайте
сервис:

```bash
grep '^NODE_RED_ADMIN_USERNAME=' .env
grep '^NODE_RED_ADMIN_PASSWORD_HASH=' .env
docker compose up -d --force-recreate
```

Не удаляйте `adminAuth` из `config/settings.js`, чтобы вернуть доступ к
публичному серверу. Создайте новый парольный хеш. Секрет credentials не влияет
на вход, но его смена делает сохранённые credentials нечитаемыми.

## Порт 1880 уже занят

Измените `NODE_RED_PORT` в `.env`, пересоздайте сервис и обновите upstream в
reverse proxy. Сохраните localhost bind:

```bash
docker compose up -d
docker compose port node-red 1880
```

## Поток не deploy или не найден узел

Откройте debug sidebar и изучите runtime-логи:

```bash
docker compose logs --tail=200 node-red
```

Устанавливайте через palette manager только проверенные узлы и экспортируйте
поток до изменений. Community-узел — исполняемый код в контейнере; удаление
пакета может сделать зависимые потоки невалидными.

## Credentials не расшифровываются после restore

Для `flows_cred.json` требуется тот же `NODE_RED_CREDENTIAL_SECRET`, который
использовался при шифровании. Верните сохранённое значение в `.env`, пересоздайте
контейнер и повторите попытку. Если старый секрет утрачен, сначала экспортируйте
потоки без секретов, удалите повреждённые credentials и введите их заново:
обхода шифрования нет.
