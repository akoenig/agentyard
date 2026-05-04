# Personal Agent Infrastructure

Docker Compose setup for running multiple isolated Hermes agents behind local Caddy TLS.

Shared services:

- Caddy reverse proxy with self-signed TLS from Caddy's internal CA
- Postgres server used by per-agent LiteLLM databases

Per agent:

- One Hermes gateway container
- One LiteLLM proxy container
- One Postgres database for LiteLLM state, virtual keys, spend, and usage logs
- One ChatGPT OAuth token directory, allowing each agent to use its own ChatGPT subscription
- One Hermes data directory mounted at `/opt/data`

## Architecture

The base stack is defined in `compose.yaml` and contains only shared infrastructure. Agent services are defined in `compose.agents.yaml`.

```text
Caddy
  -> personal-hermes-api.example.com  -> hermes-personal:8642
  -> personal-litellm-api.example.com -> litellm-personal:4000

hermes-personal -> litellm-personal -> ChatGPT subscription for personal
```

Adding another agent creates another isolated pair:

```text
hermes-research -> litellm-research -> ChatGPT subscription for research
```

Each LiteLLM instance uses its own database, for example:

```text
litellm_personal
litellm_research
litellm_work
```

## Models

Agent LiteLLM configs are generated from `litellm/models.chatgpt.yaml`. The current model list includes:

- `chatgpt/gpt-5.5`
- `chatgpt/gpt-5.5-pro`
- `chatgpt/gpt-5.4`
- `chatgpt/gpt-5.4-pro`
- `chatgpt/gpt-5.3-codex`
- `chatgpt/gpt-5.3-codex-spark`
- `chatgpt/gpt-5.3-instant`
- `chatgpt/gpt-5.3-chat-latest`

## Initial Setup

1. Create the local environment file.

```bash
cp .env.example .env
```

2. Edit `.env` and replace shared infrastructure values.

Shared settings:

- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `CADDY_HTTP_PORT`
- `CADDY_HTTPS_PORT`

LiteLLM and Hermes credentials are agent-specific. For example, the preconfigured `personal` agent uses:

- `LITELLM_PERSONAL_MASTER_KEY`
- `LITELLM_PERSONAL_SALT_KEY`
- `HERMES_PERSONAL_LITELLM_KEY`

Keep LiteLLM master and salt keys starting with `sk-`.

## Personal Agent Setup

The repository includes a preconfigured `personal` agent. Its services are `litellm-personal` and `hermes-personal`.

1. Add the personal agent hostnames to DNS or your local hosts file so they resolve to this machine.

```text
personal-litellm-api.example.com
personal-hermes-api.example.com
```

2. Start shared infrastructure and the personal LiteLLM instance.

```bash
docker compose -f compose.yaml -f compose.agents.yaml up -d caddy litellm-personal
```

3. Watch the personal LiteLLM logs for the ChatGPT device-code login URL and complete authentication in a browser.

```bash
docker compose -f compose.yaml -f compose.agents.yaml logs -f litellm-personal
```

The ChatGPT auth token for this agent is stored below `data/litellm/personal/chatgpt/` and survives container recreation.

4. Generate the personal Hermes virtual key after OAuth succeeds.

```bash
scripts/create-agent-key personal
```

This writes `HERMES_PERSONAL_LITELLM_KEY` into `.env`.

5. Start the full stack.

```bash
docker compose -f compose.yaml -f compose.agents.yaml up -d
```

## Hermes Setup

Run the Hermes setup wizard once per agent if its data directory has not been initialized:

```bash
docker compose -f compose.yaml -f compose.agents.yaml run --rm hermes-personal setup
```

Hermes receives these OpenAI-compatible settings from Compose:

```text
OPENAI_API_BASE=http://litellm-personal:4000/v1
OPENAI_API_KEY=$HERMES_PERSONAL_LITELLM_KEY
```

## Creating Agents

Make sure Postgres is running before creating a new agent so the script can create that agent's LiteLLM database:

```bash
docker compose -f compose.yaml -f compose.agents.yaml up -d postgres
```

Create an additional isolated agent with:

```bash
scripts/create-agent research
```

This creates:

- `litellm-research` service in `compose.agents.yaml` with container name `research-litellm`
- `hermes-research` service in `compose.agents.yaml` with container name `research-hermes`
- `litellm/agents/research/config.yaml`
- `caddy/agents/research.caddy`
- `data/litellm/research/`
- `data/agents/research/`
- `.env` entries for `LITELLM_RESEARCH_MASTER_KEY`, `LITELLM_RESEARCH_SALT_KEY`, and `HERMES_RESEARCH_LITELLM_KEY`

If Postgres was not running when `scripts/create-agent` ran, create the database manually before starting that agent's LiteLLM:

```bash
docker compose -f compose.yaml -f compose.agents.yaml exec postgres createdb -U litellm litellm_research
```

Then start that agent's LiteLLM and complete ChatGPT OAuth:

```bash
docker compose -f compose.yaml -f compose.agents.yaml up -d caddy litellm-research
docker compose -f compose.yaml -f compose.agents.yaml logs -f litellm-research
```

Generate its Hermes virtual key:

```bash
scripts/create-agent-key research
```

Start the Hermes agent:

```bash
docker compose -f compose.yaml -f compose.agents.yaml up -d hermes-research caddy
```

Run Hermes setup for that agent if needed:

```bash
docker compose -f compose.yaml -f compose.agents.yaml run --rm hermes-research setup
```

List configured agents:

```bash
scripts/list-agents
```

The helper scripts use standard POSIX shell tools. `scripts/create-agent-key` also requires `curl` and `python3` to call LiteLLM and extract the generated key from the JSON response.

## Local Caddy

Caddy is included in Compose and terminates TLS using Caddy's internal certificate authority via `tls internal`.

Published host ports:

- HTTP: `${CADDY_HTTP_PORT:-80}`
- HTTPS: `${CADDY_HTTPS_PORT:-443}`

The root Caddyfile imports all per-agent routes:

```caddyfile
import /etc/caddy/agents/*.caddy
```

Example per-agent route:

```caddyfile
personal-litellm-api.example.com {
  encode zstd gzip
  tls internal
  reverse_proxy litellm-personal:4000
}

personal-hermes-api.example.com {
  encode zstd gzip
  tls internal
  reverse_proxy hermes-personal:8642
}
```

Because `tls internal` uses a local CA, clients need to trust Caddy's root certificate or explicitly allow the self-signed certificate, for example with `curl --insecure` during bootstrap.

Caddy stores its internal CA and certificates under `data/caddy/`.

## Virtual Keys And Usage

Each Hermes agent gets a LiteLLM virtual key from its own LiteLLM instance. That keeps usage, spend logs, budgets, and key controls isolated per agent.

Example key metadata generated by `scripts/create-agent-key`:

```json
{
  "owner": "agent:personal",
  "type": "hermes-agent"
}
```

## Data

The `data/` directory and selected service subdirectories are committed as empty directories via `.gitkeep`. Runtime contents are ignored by git.

Important runtime locations:

- `data/caddy/` stores Caddy's local CA and certificates
- `data/postgres/` stores Postgres data
- `data/litellm/<agent>/` stores each agent's ChatGPT OAuth token directory
- `data/agents/<agent>/` stores each Hermes agent's config, sessions, memories, skills, and logs
