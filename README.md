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
- `<agent>-hermes-agent`, Hermes Agent gateway sidecar that runs scheduled jobs and reminders

Per-agent runtime state lives under `agents/<agent>/data/`:

```text
agents/hermy/
  config/
    compose.yaml
  data/
    hermes/
      hermes-agent/
      profiles/
        hermy/
          config.yaml
    workspace/
```

No agent is included by default. Always create agents with `scripts/create-agent`.

Each generated WebUI container uses the stock `ghcr.io/nesquena/hermes-webui:latest` image. WebUI runs chat in-process with the mounted Hermes home and `/workspace` bind mount.

Scheduled jobs and reminders require Hermes Agent's gateway loop. Each generated agent also runs `nousresearch/hermes-agent:latest` with `gateway run`, sharing the same agent-named Hermes profile and workspace as WebUI. The gateway is not exposed through Cloudflare; it only needs egress for model access and optional notification delivery.

WebUI also sets `HERMES_EXEC_ASK=1` so Hermes Agent exposes the `cronjob` tool during browser chats. Without that environment flag, prompts like "remind me in 10 minutes" may not be able to create scheduled jobs from WebUI chat, even though the Cron panel API is present.

Cron jobs created from WebUI browser chats do not have a messaging-platform origin like Telegram or Discord, so Hermes stores their output locally by default unless the job targets a messaging platform. For a shared notification destination, configure Telegram as the agent's home channel and ask reminders to deliver there, or select Telegram in the Cron panel. Full run output is also available from the WebUI Tasks/Cron panel.

Hermes WebUI expects Hermes Agent source in the mounted Hermes home. `scripts/create-agent` clones `https://github.com/NousResearch/hermes-agent.git` into `agents/<agent>/data/hermes/hermes-agent`, and the WebUI startup installs Hermes Agent from that checkout.

The generated compose file sets the runtime container to the configured `UID` and `GID` values, defaulting to `1000`, to keep host-mounted workspace files writable.

## Networking

The stack uses separate Docker networks to reduce lateral access:

- `tunnel`, internal network for Cloudflare Tunnel and Hermes WebUIs
- `egress`, normal bridge network for shared services that need Internet access
- `${COMPOSE_PROJECT_NAME:-agents}-<agent>`, per-agent bridge network for that agent's WebUI and gateway sidecar

Cloudflared is attached to `egress` for outbound Internet access and `tunnel` for inbound routing to WebUIs. Each Hermes WebUI is attached to `tunnel` plus its own per-agent bridge network. Each Hermes gateway sidecar is attached only to its own per-agent bridge network.

Per-agent bridge networks are intentionally not shared across agents. They provide outbound Internet access for that agent's containers without putting all agents on one common egress network.

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
- `agents/hermy/data/hermes/active_profile`
- `agents/hermy/data/hermes/hermes-agent/`
- `agents/hermy/data/hermes/profiles/hermy/config.yaml`
- `agents/hermy/data/hermes/webui/settings.json`
- `agents/hermy/data/workspace/`
- empty `.env` entry for the Hermes WebUI password, disabled by default because Cloudflare Access is expected to protect the hostname
- empty `.env` entries for an optional Telegram home channel

During creation, the script starts the OpenAI Codex device-code login with the official `nousresearch/hermes-agent` image mounted against the same Hermes home. Open the shown URL, enter the displayed code, and approve the ChatGPT subscription login.

Hermes stores the OAuth credentials in the agent-named active profile:

```text
agents/hermy/data/hermes/profiles/hermy/auth.json
```

After login succeeds, the script starts `cloudflared` and `hermy-hermes-webui`.
It also starts `hermy-hermes-agent`, which runs `hermes gateway run` for reminders and cron jobs.

### 3. Optional Telegram Home Channel

Hermes Agent has a native Telegram home channel. Cron delivery target `telegram` sends scheduled task results to that home channel.

Create a Telegram bot with BotFather, add the bot to the chat you want to use, then configure the generated entries in the repository-local `.env` file. On the server this is usually `/root/personal-agent/.env`.

For agent `hermy`, the entries look like this:

```bash
HERMES_HERMY_TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrSTUvwxYZ
HERMES_HERMY_TELEGRAM_ALLOWED_USERS=123456789
HERMES_HERMY_TELEGRAM_HOME_CHANNEL=123456789
HERMES_HERMY_TELEGRAM_HOME_CHANNEL_NAME=General
```

`HERMES_HERMY_TELEGRAM_BOT_TOKEN` is the bot token from `@BotFather`.

`HERMES_HERMY_TELEGRAM_ALLOWED_USERS` is a comma-separated list of numeric Telegram user IDs allowed to use the bot. Get your ID from `@userinfobot`, for example `123456789` or `123456789,987654321` for multiple users.

`HERMES_HERMY_TELEGRAM_HOME_CHANNEL` is the home delivery target. For a personal DM with the bot, this is usually your Telegram user ID. For Telegram groups, the chat ID is usually a negative number like `-1001234567890`.

`HERMES_HERMY_TELEGRAM_HOME_CHANNEL_NAME` is only a display name. Use something like `General`, `Hermy`, or `Notifications`.

As an alternative to setting `HERMES_HERMY_TELEGRAM_HOME_CHANNEL` manually, restart the gateway after adding the bot token and allowed users, then send `/sethome` in the Telegram chat you want to use as the home channel.

Restart the gateway sidecar after editing `.env`:

```bash
docker compose -f compose.yaml -f agents/hermy/config/compose.yaml up -d --force-recreate hermy-hermes-agent
```

Telegram-origin reminders naturally deliver back to Telegram. WebUI-origin reminders need an explicit delivery target, for example: "remind me in 10 minutes and deliver it to Telegram" or the Cron panel's Telegram delivery option. For a specific Telegram topic instead of the home channel, use Hermes' direct target format `telegram:<chat_id>:<thread_id>`.

### 4. Verify Hermes Codex Configuration

The generated Hermes config selects the native Codex provider:

```yaml
model:
  provider: openai-codex
  default: gpt-5.5
terminal:
  backend: local
  cwd: /workspace
```

Verify the running runtime sees the expected state path and provider overrides:

```bash
docker exec hermy-hermes-webui sh -lc 'env | grep -E "HERMES_HOME|HERMES_WEBUI_SKIP_ONBOARDING|HERMES_INFERENCE_PROVIDER|HERMES_INFERENCE_MODEL"'
```

Expected values include:

```text
HERMES_HOME=/home/hermeswebui/.hermes
HERMES_WEBUI_SKIP_ONBOARDING=1
HERMES_INFERENCE_PROVIDER=openai-codex
HERMES_INFERENCE_MODEL=gpt-5.5
```

Verify the reminder scheduler sidecar is running against the agent-named profile:

```bash
docker exec hermy-hermes-agent sh -lc 'printf "%s\n" "$HERMES_HOME"'
```

Expected value:

```text
/home/hermes/.hermes/profiles/hermy
```

Generated agents also preseed WebUI defaults:

- notification sound enabled
- browser notifications enabled, subject to the browser permission prompt
- token usage visible after responses

### 5. Verify Workspace Mount

The agent workspace is mounted into the runtime at `/workspace` and persisted on the host at `agents/hermy/data/workspace/`.

Test the mount:

```bash
docker exec hermy-hermes-webui sh -lc 'date > /workspace/mount-test.txt && ls -la /workspace/mount-test.txt'
ls -la agents/hermy/data/workspace/mount-test.txt
```

If the container cannot write to `/workspace`, make sure `.env` has the correct `UID` and `GID`, then recreate the runtime.

### 6. Configure Cloudflare Tunnel

Each agent should have one Cloudflare Tunnel public hostname:

```text
Hostname: hermy.agents.example.com
Service:  http://hermy-hermes-webui:8787
```

Use one shared tunnel connector for the host and add one public hostname per agent.

### 7. Configure Cloudflare Access

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

Hermes WebUI gets a per-agent password variable in `.env`, but it is empty by default:

```bash
HERMES_HERMY_WEBUI_PASSWORD=
```

This disables the WebUI's own password and relies on Cloudflare Access as the authentication layer. To enable the extra WebUI password, set a value and recreate the WebUI runtime:

```bash
HERMES_HERMY_WEBUI_PASSWORD=<strong-password>
docker compose -f compose.yaml -f agents/hermy/config/compose.yaml up -d --force-recreate hermy-hermes-webui
```

Keeping both Cloudflare Access and the Hermes WebUI password is possible, but Hermes WebUI's login page probes `/health` without credentials. If Cloudflare Access protects `/health`, the browser can show `Cannot reach server`. To keep the second password, add a Cloudflare Access bypass only for `/health`.

### 8. Open The WebUI

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

Both scripts update the mounted Hermes Agent checkout, pull the configured Agent and WebUI images, and recreate the gateway and WebUI containers. Recreating the WebUI container is intentional: the upstream WebUI Docker startup installs Hermes Agent dependencies into the container venv, so dependency changes require a fresh container.

To pin or roll back Hermes Agent to a specific ref:

```bash
scripts/update-agent hermy <tag-or-sha>
scripts/update-agents <tag-or-sha>
```

## Models

New agents default to Hermes' native OpenAI Codex provider with `gpt-5.5`.

To change the model after creation, edit `agents/<agent>/data/hermes/profiles/<agent>/config.yaml` or use Hermes' model picker inside the container.
