## Startup, permissions, or healthcheck failure

Run `docker compose ps`, `docker compose logs --tail=100 open-webui ollama`, and `docker compose config --quiet`. Check free disk/RAM, pinned tags, and that the permissions helper completed. The app healthcheck uses `/health/db`; Ollama uses `ollama list`. Both data volumes must be writable by UID/GID 1000. Do not remove authentication or run privileged to bypass a permissions problem.

## No models or no answer

A healthy Ollama is not a downloaded model. Run `docker compose exec ollama ollama list`, pull the reviewed example, and refresh Open WebUI's model list. Check the local provider URL `http://ollama:11434`; this is an internal address, not a browser URL. `OLLAMA_NO_CLOUD=true` deliberately disables cloud use. Large models, long contexts, and several simultaneous requests can exhaust RAM. Inspect `docker stats` and the logs; use a smaller model/context or a larger server.

## Wrong password or registration policy

The bootstrap password/email applies only to an empty user database. Change an existing password in the UI, not by editing the initial environment. Registration starts disabled, but saved UI settings can override defaults. Review the administrator security/provider settings after updates and recovery. The recipe does not supply shared login credentials.

## CORS, websocket, or proxy errors

Match `OPEN_WEBUI_URL` to the exact browser origin. Check websocket upgrades and proxy timeouts. `OPEN_WEBUI_TRUSTED_PROXIES` must name the actual forwarding proxy; do not use `*`. A containerized proxy cannot reach the host's loopback by using its own `127.0.0.1`. Never expose the Ollama API to fix a browser proxy issue.

## Missing files, chats, or models after recovery

Restore the complete backup archive containing both data payloads with the original service secret and matching app/Ollama versions. A chat export omits uploads, model weights, and settings. Re-login, open a saved chat, download a file, and test generation. Compare the archived environment by hand. Preserve the current volumes and the safety backup while investigating.

Sources: [environment configuration](https://docs.openwebui.com/getting-started/env-configuration/), [documentation](https://docs.openwebui.com/), [Ollama](https://github.com/ollama/ollama).
