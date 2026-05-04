# Personal Agent Infrastructure

Docker Compose setup for a personal agent stack:

- LiteLLM proxy backed by Postgres for virtual keys
- ChatGPT subscription/Codex models through LiteLLM OAuth device flow
- Hermes Agent gateway

Services bind to `HOST_BIND_ADDRESS`, which defaults to `0.0.0.0` because Caddy is expected to run on a different host. Restrict access to the Caddy host with a firewall.

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

4. Start LiteLLM and Postgres first.

```bash
docker compose up litellm
```

5. Watch the LiteLLM logs for the ChatGPT device-code login URL and complete authentication in a browser.

```bash
docker compose logs -f litellm
```

The ChatGPT auth token is stored below `data/litellm/chatgpt/` and survives container recreation.

6. Verify LiteLLM with the master key.

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"chatgpt/gpt-5.3-codex","messages":[{"role":"user","content":"Say hello"}]}'
```

## Virtual Keys

This setup uses the `litellm-database` image and Postgres because LiteLLM virtual keys require database-backed proxy state.

Create one key for Hermes:

```bash
curl http://127.0.0.1:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"models":["chatgpt/gpt-5.5","chatgpt/gpt-5.5-pro","chatgpt/gpt-5.4","chatgpt/gpt-5.4-pro","chatgpt/gpt-5.3-codex","chatgpt/gpt-5.3-codex-spark","chatgpt/gpt-5.3-instant","chatgpt/gpt-5.3-chat-latest"],"metadata":{"owner":"hermes"}}'
```

Create one key for the other frontend:

```bash
curl http://127.0.0.1:4000/key/generate \
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

## Reverse Proxy

The host ports are bound to `HOST_BIND_ADDRESS` so a Caddy instance on another host can reach them:

- LiteLLM: `$HOST_BIND_ADDRESS:4000`
- Hermes gateway: `$HOST_BIND_ADDRESS:8642`

Terminate TLS and public access control in Caddy. Do not expose these ports broadly; firewall them so only the Caddy host can connect.

An example Caddy config is available at `caddy/Caddyfile.example`. Replace the example domains, email, and `personal-agent-host.example.com` upstream before use:

```caddyfile
{
  email admin@example.com
}

hermy-litellm-api.example.com {
  encode zstd gzip
  reverse_proxy personal-agent-host.example.com:4000
}

hermy-hermes-api.example.com {
  encode zstd gzip
  reverse_proxy personal-agent-host.example.com:8642
}
```

## Data

The `data/` directory and service subdirectories are committed as empty directories via `.gitkeep`. Runtime contents are ignored by git.
