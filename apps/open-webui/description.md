## A browser interface for your own language models

Open WebUI gives local models a browser chat interface with conversation history, files, and knowledge collections. It suits people who want to keep household notes, drafts, and ordinary AI conversations on their own server. It replaces the hosted-chat workflow of services such as ChatGPT or Claude; it does not include those services' proprietary models or promise their answer quality.

This recipe runs the official Open WebUI image with a separate, internal Ollama server on CPU. No cloud API key is required. A model is downloaded separately: the small `qwen3:0.6b` example is suitable for checking the setup, not a benchmark for demanding work. Plan for two CPU cores, 4 GB RAM (8 GB recommended), and 10 GB disk before larger models, growing data, and backups. These are planning estimates. Both images support amd64/arm64; only amd64 was exercised.

## Data and security

<!-- coverage:security-assessment -->

The administrator is created from private `.env` values at first startup; there is no shared default password. Registration and external OpenAI-compatible providers start disabled. Ollama has no host port and cloud use is disabled. The recipe runs both servers as UID/GID 1000 with read-only root filesystems, writable data volumes, and temporary storage. Preserve `OPEN_WEBUI_SECRET` across updates and recovery: it protects sessions and encrypted settings.

Ordinary model chats, files, and settings are server-side data, not end-to-end encrypted by this recipe. Administrator Functions and Tools can run server-side code; grant that role only to trusted people. OIDC, MFA, and trusted-header login exist upstream but are not configured here. Do not enable trusted-header authentication behind a proxy that accepts client-supplied identity headers. Image CVEs have not been scanned and remain unknown.

A healthy web page does not prove that a model works. The amd64 smoke performs real local generation, saves a chat and file, removes both volumes, restores them, verifies the exact file and model digest, and generates another response. It does not benchmark accuracy, GPU support, large models, voice, or RAG retrieval. Model output can be wrong: review it before using it.

## License and operations

The Open WebUI License contains BSD-style terms plus branding conditions, so the catalog records it as source available. The 50-user threshold concerns permission to change branding; ordinary use with the original branding is not capped at 50 users. This recipe keeps the application's branding. Ollama uses MIT; the downloaded Qwen3 0.6B example uses Apache-2.0. Other models may have other restrictions.

One backup archives both persistent volumes and the active configuration while both writers are stopped. It includes SQLite, uploads, local vector/cache data, model weights, and secrets. Saved UI configuration can override initial environment defaults; inspect registration, providers, and sharing permissions after recovery. Read release notes before each update and restore the pre-update data with matching versions for rollback.

Sources: [Open WebUI documentation](https://docs.openwebui.com/), [v0.12.3](https://github.com/open-webui/open-webui/releases/tag/v0.12.3), [license](https://github.com/open-webui/open-webui/blob/v0.12.3/LICENSE), [Ollama](https://github.com/ollama/ollama), [Qwen3 0.6B](https://huggingface.co/Qwen/Qwen3-0.6B). The catalog SVG mark is the Open WebUI icon from [LobeHub Icons](https://github.com/lobehub/lobe-icons); the running app's branding is unchanged.
