# Personal Agent Infrastructure

Docker Compose infrastructure for running multiple isolated Hermes WebUI runtimes. Each agent uses the recommended upstream Hermes WebUI single-container Docker setup and authenticates directly with the OpenAI Codex provider using a ChatGPT subscription login.

Public access is WebUI-only through Cloudflare Tunnel:

```text
Browser
  -> https://<agent>.$AGENT_BASE_DOMAIN
  -> Cloudflare Access Google Auth
  -> Cloudflare Tunnel
  -> <agent>-hermes-webui:8787
```

## Architecture

Shared services in `compose.yaml`:

- `cloudflared`, shared Cloudflare Tunnel connector

Per-agent services in `agents/<agent>/config/compose.yaml`:

- `<agent>-hermes-webui`, upstream Hermes WebUI single-container runtime reached only through Cloudflare Tunnel

Per-agent runtime state lives under `agents/<agent>/data/`:

```text
agents/hermy/
  config/
    compose.yaml
  data/
    hermes/
      hermes-agent/
    workspace/
```

No agent is included by default. Always create agents with `scripts/create-agent`.

Each generated WebUI container uses the stock `ghcr.io/nesquena/hermes-webui:latest` image. This follows the upstream recommended single-container setup: WebUI runs the agent in-process with the mounted Hermes home and `/workspace` bind mount.

Hermes WebUI expects Hermes Agent source in the mounted Hermes home. `scripts/create-agent` clones `https://github.com/NousResearch/hermes-agent.git` into `agents/<agent>/data/hermes/hermes-agent`, and the WebUI startup installs Hermes Agent from that checkout.

The generated compose file sets the runtime container to the configured `UID` and `GID` values, defaulting to `1000`, to keep host-mounted workspace files writable.

## Networking

The stack uses separate Docker networks to reduce lateral access:

- `tunnel`, internal network for Cloudflare Tunnel and Hermes WebUIs
- `egress`, normal bridge network for services that need Internet access

Hermes WebUI runtimes and cloudflared are attached to `egress` for outbound Internet access. Cloudflared reaches each WebUI over `tunnel`.

## Step-By-Step Setup

Run all commands from the repository root.

### 1. Configure Local Environment

Create the local environment file:

```bash
cp .env.example .env
chmod go-rwx .env*
```

Edit `.env`:

```bash
COMPOSE_PROJECT_NAME=agents
AGENT_BASE_DOMAIN=agents.example.com
CLOUDFLARE_TUNNEL_TOKEN=<cloudflare-tunnel-token>
```

Optional defaults can be pinned in `.env`:

```bash
HERMES_WEBUI_IMAGE=ghcr.io/nesquena/hermes-webui:latest
HERMES_AGENT_IMAGE=nousresearch/hermes-agent:latest
HERMES_AGENT_REPO=https://github.com/NousResearch/hermes-agent.git
HERMES_AGENT_REF=main
```

If the host user that should own workspace files is not UID/GID `1000`, add matching values:

```bash
UID=$(id -u)
GID=$(id -g)
```

### 2. Create An Agent

Create an isolated agent:

```bash
scripts/create-agent hermy
```

This creates:

- `agents/hermy/config/compose.yaml`
- `agents/hermy/data/hermes/config.yaml`
- `agents/hermy/data/hermes/hermes-agent/`
- `agents/hermy/data/workspace/`
- `.env` entry for the Hermes WebUI password

During creation, the script starts the OpenAI Codex device-code login with the official `nousresearch/hermes-agent` image mounted against the same Hermes home. Open the shown URL, enter the displayed code, and approve the ChatGPT subscription login.

Hermes stores the OAuth credentials in:

```text
agents/hermy/data/hermes/auth.json
```

After login succeeds, the script starts `cloudflared` and `hermy-hermes-webui`.

### 3. Verify Hermes Codex Configuration

The generated Hermes config selects the native Codex provider:

```yaml
model:
  provider: openai-codex
  model: gpt-5.3-codex
terminal:
  backend: local
  cwd: /workspace
```

Verify the running runtime sees the expected state path and provider overrides:

```bash
docker exec hermy-hermes-webui sh -lc 'env | grep -E "HERMES_HOME|HERMES_INFERENCE_PROVIDER|HERMES_INFERENCE_MODEL"'
```

Expected values include:

```text
HERMES_HOME=/home/hermeswebui/.hermes
HERMES_INFERENCE_PROVIDER=openai-codex
HERMES_INFERENCE_MODEL=gpt-5.3-codex
```

### 4. Verify Workspace Mount

The agent workspace is mounted into the runtime at `/workspace` and persisted on the host at `agents/hermy/data/workspace/`.

Test the mount:

```bash
docker exec hermy-hermes-webui sh -lc 'date > /workspace/mount-test.txt && ls -la /workspace/mount-test.txt'
ls -la agents/hermy/data/workspace/mount-test.txt
```

If the container cannot write to `/workspace`, make sure `.env` has the correct `UID` and `GID`, then recreate the runtime.

### 5. Configure Cloudflare Tunnel

Each agent should have one Cloudflare Tunnel public hostname:

```text
Hostname: hermy.agents.example.com
Service:  http://hermy-hermes-webui:8787
```

Use one shared tunnel connector for the host and add one public hostname per agent.

### 6. Configure Cloudflare Access

Protect each agent hostname with Cloudflare Access and Google Auth.

Configure Google as a Cloudflare Access login method:

1. Open the Cloudflare Zero Trust dashboard at `https://one.dash.cloudflare.com/`.
2. Select the Cloudflare account that owns the tunnel and Access applications.
3. Go to `Integrations` -> `Identity providers`.
4. Select `Add new identity provider`, then choose `Google`.
5. If the dashboard uses the older layout, use `Settings` -> `Authentication` -> `Login methods` instead.
6. Create a Google OAuth app in Google Cloud with application type `Web application`.
7. Set the authorized JavaScript origin to the Cloudflare Access team domain:

```text
https://<your-team-name>.cloudflareaccess.com
```

8. Set the authorized redirect URI to the Cloudflare Access callback URL:

```text
https://<your-team-name>.cloudflareaccess.com/cdn-cgi/access/callback
```

9. Copy the Google OAuth client ID and client secret into Cloudflare.
10. Enable `Proof Key for Code Exchange (PKCE)`.
11. Save the identity provider and use Cloudflare's `Test` action for Google.

Restrict access per agent with a dedicated Access application:

1. Go to `Access controls` -> `Applications`.
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

When using Cloudflare Access, the simplest setup is to remove or empty that password and recreate the WebUI runtime:

```bash
HERMES_HERMY_WEBUI_PASSWORD=
docker compose -f compose.yaml -f agents/hermy/config/compose.yaml up -d --force-recreate hermy-hermes-webui
```

Keeping both Cloudflare Access and the Hermes WebUI password is possible, but Hermes WebUI's login page probes `/health` without credentials. If Cloudflare Access protects `/health`, the browser can show `Cannot reach server`. To keep the second password, add a Cloudflare Access bypass only for `/health`.

### 7. Open The WebUI

Open the agent hostname in a browser:

```text
https://hermy.agents.example.com
```

After Cloudflare Access succeeds, Hermes WebUI should load. The browser does not receive OpenAI OAuth tokens; they remain in the agent's mounted Hermes home.

## Data And Secrets

Runtime contents are ignored by git. Important paths:

- `agents/<agent>/data/hermes/`, Hermes state and Codex OAuth credentials
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

This stops and removes the per-agent WebUI container, deletes `agents/hermy/`, and removes the agent-specific `.env` entry.

## Updating Agents

Update one agent:

```bash
scripts/update-agent hermy
```

Update all agents:

```bash
scripts/update-agents
```

Both scripts update the mounted Hermes Agent checkout, pull the configured WebUI image, and recreate the WebUI container. Recreating the container is intentional: the upstream WebUI Docker startup installs Hermes Agent dependencies into the container venv, so dependency changes require a fresh container.

To pin or roll back Hermes Agent to a specific ref:

```bash
scripts/update-agent hermy <tag-or-sha>
scripts/update-agents <tag-or-sha>
```

## Models

New agents default to Hermes' native OpenAI Codex provider with `gpt-5.3-codex`.

To change the model after creation, edit `agents/<agent>/data/hermes/config.yaml` or use Hermes' model picker inside the container.
