# Personal Agent Infrastructure

Docker Compose setup for a personal agent stack:

- LiteLLM proxy backed by Postgres for virtual keys
- ChatGPT subscription/Codex models through LiteLLM OAuth device flow
- Hermes Agent gateway
- Local Caddy reverse proxy with self-signed TLS from Caddy's internal CA

LiteLLM and Hermes are only exposed on the internal Docker network. Caddy publishes ports `80` and `443`, terminates TLS locally, and proxies to the services by Compose service name.

## Models

LiteLLM is configured for ChatGPT subscription models using the `chatgpt/` provider route. The config includes the latest expected `gpt-5.5` names plus the `gpt-5.4` and `gpt-5.3` models currently shown in LiteLLM's ChatGPT provider docs.

Configured models:

- `chatgpt/gpt-5.5`
- `chatgpt/gpt-5.5-pro`
- `chatgpt/gpt-5.4`
- `chatgpt/gpt-5.4-pro`
- `chatgpt/gpt-5.3-codex`
- `chatgpt/gpt-5.3-codex-spark`
- `chatgpt/gpt-5.3-instant`
- `chatgpt/gpt-5.3-chat-latest`

## Bootstrap

1. Create the local environment file.

```bash
cp .env.example .env
```

2. Edit `.env` and replace all `change-me` values. Keep `LITELLM_MASTER_KEY` and `LITELLM_SALT_KEY` starting with `sk-`.

3. Load `.env` into the current shell for the `curl` commands below.

```bash
set -a
. ./.env
set +a
```

4. Start Caddy, LiteLLM, and Postgres first.

```bash
docker compose up -d caddy litellm
```

5. Watch the LiteLLM logs for the ChatGPT device-code login URL and complete authentication in a browser.

```bash
docker compose logs -f litellm
```

The ChatGPT auth token is stored below `data/litellm/chatgpt/` and survives container recreation.

6. Verify LiteLLM with the master key.

```bash
curl --insecure https://hermy-litellm-api.example.com/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"chatgpt/gpt-5.3-codex","messages":[{"role":"user","content":"Say hello"}]}'
```

## Virtual Keys

This setup uses the `litellm-database` image and Postgres because LiteLLM virtual keys require database-backed proxy state.

Create one key for Hermes:

```bash
curl --insecure https://hermy-litellm-api.example.com/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"models":["chatgpt/gpt-5.5","chatgpt/gpt-5.5-pro","chatgpt/gpt-5.4","chatgpt/gpt-5.4-pro","chatgpt/gpt-5.3-codex","chatgpt/gpt-5.3-codex-spark","chatgpt/gpt-5.3-instant","chatgpt/gpt-5.3-chat-latest"],"metadata":{"owner":"hermes"}}'
```

Create one key for the other frontend:

```bash
curl --insecure https://hermy-litellm-api.example.com/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"models":["chatgpt/gpt-5.5","chatgpt/gpt-5.5-pro","chatgpt/gpt-5.4","chatgpt/gpt-5.4-pro","chatgpt/gpt-5.3-codex","chatgpt/gpt-5.3-codex-spark","chatgpt/gpt-5.3-instant","chatgpt/gpt-5.3-chat-latest"],"metadata":{"owner":"frontend"}}'
```

Put the Hermes key into `.env` as `HERMES_LITELLM_KEY`, then start the full stack:

```bash
docker compose up -d
```

## Hermes Setup

Run the Hermes setup wizard once if its data directory has not been initialized:

```bash
docker compose run --rm hermes setup
```

Hermes receives these OpenAI-compatible settings from Compose:

```text
OPENAI_API_BASE=http://litellm:4000/v1
OPENAI_API_KEY=$HERMES_LITELLM_KEY
```

## Local Caddy

Caddy is included in Compose and terminates TLS using Caddy's internal certificate authority via `tls internal`.

Published host ports:

- HTTP: `${CADDY_HTTP_PORT:-80}`
- HTTPS: `${CADDY_HTTPS_PORT:-443}`

Configured hostnames:

- `hermy-litellm-api.example.com` -> LiteLLM
- `hermy-hermes-api.example.com` -> Hermes gateway API

Add these hostnames to DNS or your local hosts file so they resolve to this machine. Because `tls internal` uses a local CA, clients need to trust Caddy's root certificate or explicitly allow the self-signed certificate, for example with `curl --insecure` during bootstrap.

The Caddy config is available at `caddy/Caddyfile.example`:

```caddyfile
hermy-litellm-api.example.com {
  encode zstd gzip
  tls internal
  reverse_proxy litellm:4000
}

hermy-hermes-api.example.com {
  encode zstd gzip
  tls internal
  reverse_proxy hermes:8642
}
```

Caddy stores its internal CA and certificates under `data/caddy/`.

## Data

The `data/` directory and service subdirectories are committed as empty directories via `.gitkeep`. Runtime contents are ignored by git.
