# Personal Agent Infrastructure

Docker Compose infrastructure for running multiple isolated Hermes agents with one Hermes WebUI per agent.

Public access is WebUI-only through Cloudflare Tunnel:

```text
Browser
  -> https://<agent>.$AGENT_BASE_DOMAIN
  -> Cloudflare Access Google Auth
  -> Cloudflare Tunnel
  -> <agent>-hermes-webui:8787
```

LiteLLM and Hermes APIs are internal-only and are not exposed publicly.

## Architecture

Shared services in `compose.yaml`:

- `postgres`, shared database server for per-agent LiteLLM databases
- `cloudflared`, shared Cloudflare Tunnel connector

Per-agent services in `agents/<agent>/config/compose.yaml`:

- `<agent>-litellm`, private LiteLLM proxy
- `<agent>-hermes`, private Hermes gateway/API server
- `<agent>-hermes-webui`, public user-facing UI reached only through Cloudflare Tunnel

Per-agent runtime state lives under `agents/<agent>/data/`:

```text
agents/hermy/
  config/
    compose.yaml
    litellm.yaml
  data/
    hermes/
    litellm/
    webui/
    workspace/
```

No agent is included by default. Always create agents with `scripts/create-agent`.

## Networking

The stack uses separate Docker networks to reduce lateral access:

- `db`, internal network for Postgres and LiteLLM services
- `tunnel`, internal network for Cloudflare Tunnel and Hermes WebUIs
- `egress`, normal bridge network for services that need Internet access
- `<agent>-agent`, internal per-agent network for that agent's LiteLLM, Hermes, and WebUI

Hermes and LiteLLM are attached to `egress` because they need outbound Internet access. Cloudflared is attached to `egress` to reach Cloudflare. Cloudflared is not attached to the per-agent private networks, so it can only reach each WebUI over `tunnel`.

## Initial Setup

Create the local environment file:

```bash
cp .env.example .env
chmod go-rwx .env*
```

Edit `.env`:

```bash
COMPOSE_PROJECT_NAME=agents
POSTGRES_DB=postgres
POSTGRES_USER=litellm
POSTGRES_PASSWORD=<strong-password>
AGENT_BASE_DOMAIN=agents.example.com
CLOUDFLARE_TUNNEL_TOKEN=<cloudflare-tunnel-token>
```

Start shared infrastructure:

```bash
docker compose up -d postgres cloudflared
```

Postgres initializes `data/postgres/` on first start. That directory must be empty before first successful initialization.

## Creating An Agent

Create an isolated agent:

```bash
scripts/create-agent hermy
```

This creates:

- `agents/hermy/config/compose.yaml`
- `agents/hermy/config/litellm.yaml`
- `agents/hermy/data/hermes/`
- `agents/hermy/data/litellm/`
- `agents/hermy/data/webui/`
- `agents/hermy/data/workspace/`
- `.env` entries for LiteLLM, Hermes, and Hermes WebUI secrets
- Postgres database `litellm_hermy`, if Postgres is running

Start the agent:

```bash
docker compose -f compose.yaml -f agents/hermy/config/compose.yaml up -d postgres cloudflared hermy-litellm hermy-hermes hermy-hermes-webui
```

Create the Hermes LiteLLM virtual key after LiteLLM is running and ChatGPT/provider setup is complete:

```bash
scripts/create-agent-key hermy
```

Then recreate Hermes and WebUI so they pick up the generated LiteLLM key:

```bash
docker compose -f compose.yaml -f agents/hermy/config/compose.yaml up -d --force-recreate hermy-hermes hermy-hermes-webui
```

## Cloudflare Tunnel

Each agent should have one Cloudflare Tunnel public hostname:

```text
Hostname: hermy.agents.example.com
Service:  http://hermy-hermes-webui:8787
```

Use one shared tunnel connector for the host and add one public hostname per agent.

## Cloudflare Access

Protect each agent hostname with Cloudflare Access and Google Auth.

Configure Google as a Cloudflare Access login method:

1. Open Cloudflare Zero Trust.
2. Go to `Settings` -> `Authentication`.
3. Under `Login methods`, add `Google Workspace` or `Google`.
4. Follow Cloudflare's instructions to create the Google OAuth app in Google Cloud.
5. Configure the Google OAuth consent screen for the OpenFormation organization.
6. Add Cloudflare's callback URL from the login-method setup as an authorized redirect URI in Google Cloud.
7. Copy the Google client ID and client secret back into Cloudflare.
8. Save the login method and test authentication.

Restrict access per agent with a dedicated Access application:

1. Go to `Access` -> `Applications`.
2. Create a `Self-hosted` application.
3. Set the application domain to the agent hostname, for example `hermy.agents.example.com`.
4. Add an `Allow` policy.
5. In `Include`, choose `Emails` and add exactly the assigned user, for example `specific-user@openformation.io`.
6. Do not add broad `Everyone`, `Emails ending in`, or organization-wide allow rules unless that agent should be shared.
7. Save the application.

Recommended policy per agent:

```text
Application: hermy.agents.example.com
Policy: Allow
Include: Emails
Email: specific-user@openformation.io
```

Only that specific user should be allowed to access that agent's WebUI. Non-matching users are denied by Cloudflare Access before traffic reaches the Docker host.

Hermes WebUI also gets a generated per-agent password in `.env`:

```bash
HERMES_HERMY_WEBUI_PASSWORD=sk-...
```

That gives a second layer after Cloudflare Access. If you want Google Auth only, remove or empty the password for that agent and recreate the WebUI, but the safer default is to keep both.

## Data And Secrets

Runtime contents are ignored by git. Important paths:

- `data/postgres/`, shared Postgres data
- `agents/<agent>/data/hermes/`, Hermes state
- `agents/<agent>/data/litellm/`, LiteLLM runtime data and provider tokens
- `agents/<agent>/data/webui/`, Hermes WebUI state
- `agents/<agent>/data/workspace/`, default WebUI workspace

Keep `.env*` files restricted:

```bash
chmod go-rwx .env*
```

## Listing And Deleting Agents

List configured agents:

```bash
scripts/list-agents
```

Delete an agent and its local runtime data:

```bash
scripts/delete-agent hermy
```

This stops and removes the per-agent containers, deletes `agents/hermy/`, removes the agent-specific `.env` entries, and drops the `litellm_hermy` database if Postgres is running.

## Models

Agent LiteLLM configs are generated from `config/litellm/models.chatgpt.yaml`.

LiteLLM remains private. Hermes uses the internal endpoint:

```text
http://<agent>-litellm:4000/v1
```

The browser never receives LiteLLM or Hermes API keys.
