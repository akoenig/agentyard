# Agentyard

Agentyard makes it easy to create and operate isolated Hermes Agent + Hermes WebUI agents on one Linux host.

The runtime model is intentionally simple:

- `minder` is the non-root control-plane user.
- each agent is its own non-root Linux user, for example `hermy` or `coder`.
- Cloudflare Tunnel runs as the non-root `minder` user.
- Hermes Agent, Hermes WebUI, credentials, memory, cron jobs, and workspace files live inside each agent user's home directory.
- no Docker is used.

## Architecture

```text
Browser
  -> https://hermy.agents.example.com
  -> Cloudflare Access
  -> Cloudflare Tunnel owned by minder
  -> http://127.0.0.1:8787
  -> agentyard-webui.service owned by hermy
```

Users and services:

```text
minder
  agentyard-cloudflared.service
  ~/agentyard
  ~/agentyard/agents/hermy/agent.env

hermy
  agentyard-webui.service
  agentyard-gateway.service
  ~/.hermes
  ~/hermes-webui
  ~/workspace
```

Root is only needed for one-time control-plane bootstrap and narrow OS account operations through `/usr/local/sbin/agentyard-user`. No long-running daemon runs as root.

## Requirements

You need:

- a Linux host with `systemd`
- root or sudo access for the initial bootstrap only
- `git`, `curl`, `python3`, `python3-venv`, and `sudo`
- `cloudflared` installed if Agentyard should manage the tunnel service
- a Cloudflare account with a Tunnel and Access available
- a domain routed through Cloudflare, for example `agents.example.com`
- a ChatGPT subscription that can authenticate the Hermes `openai-codex` provider

Recommended host model:

- one host per human user
- many agent users on that host
- each agent hostname protected by Cloudflare Access

## Step 1: Bootstrap The Control Plane

Clone the repository as any temporary/admin user, then run the bootstrap with root privileges:

```bash
sudo scripts/install-control-plane
```

This creates:

- Linux user `minder`
- system group `agentyard-agents`
- root-owned helper `/usr/local/sbin/agentyard-user`
- sudoers rule allowing `minder` to run only that helper without a password
- lingering for `minder`, so its user services can run after logout

Then switch to `minder` and put the repo in its home directory:

```bash
sudo -iu minder
git clone <this-repo-url> ~/agentyard
cd ~/agentyard
```

## Step 2: Configure Agentyard

Run the control-plane installer as `minder`:

```bash
scripts/install
```

The installer creates `.env` from `.env.example` if needed and asks for missing required values.

You will be prompted for:

- `AGENT_BASE_DOMAIN`, for example `agents.example.com`
- `AGENT_BASE_PORT`, for example `8787`
- `CLOUDFLARE_TUNNEL_TOKEN`, optional but recommended if Agentyard should run `cloudflared`

If `CLOUDFLARE_TUNNEL_TOKEN` is set and `cloudflared` exists on the host, the installer creates and starts:

```text
~minder/.config/systemd/user/agentyard-cloudflared.service
```

The Cloudflare Tunnel daemon runs as `minder`, not root.

## Step 3: Create An Agent

Create an agent as `minder`:

```bash
scripts/create-agent hermy
```

This creates Linux user `hermy`, locks its password, enables lingering, installs Hermes Agent and Hermes WebUI into `hermy`'s home directory, and creates these user services:

```text
~hermy/.config/systemd/user/agentyard-webui.service
~hermy/.config/systemd/user/agentyard-gateway.service
```

The script also configures Hermes Agent for Codex:

```yaml
model:
  provider: openai-codex
  default: gpt-5.5
terminal:
  backend: local
  cwd: /home/hermy/workspace
```

During creation, Agentyard starts the OpenAI Codex OAuth flow as the `hermy` user. Open the shown URL, enter the code, and approve the ChatGPT subscription login.

The script also asks whether to configure Telegram delivery. If you choose yes, it asks for:

- Telegram bot token from `@BotFather`
- allowed Telegram user IDs, comma-separated
- optional home channel/chat ID

You can skip Telegram and configure it later.

## Step 4: Configure Cloudflare Route

After agent creation, the script prints the Cloudflare route to add:

```text
Hostname: hermy.agents.example.com
Service:  http://127.0.0.1:8787
```

Add that public hostname to your Cloudflare Tunnel. Then protect the hostname with a Cloudflare Access application.

Recommended Access policy:

```text
Application: hermy.agents.example.com
Policy: Allow
Include: Emails
Email: assigned-user@example.com
```

Each WebUI listens only on `127.0.0.1`, so the host does not expose WebUI ports directly to the public network.

## Step 5: Open WebUI

Open:

```text
https://hermy.agents.example.com
```

Cloudflare Access authenticates the browser. Hermes WebUI then talks to the Hermes runtime owned by the `hermy` Linux user.

## Telegram Home Channel

Telegram settings live inside the agent user's Hermes profile:

```bash
sudo -iu hermy
nano ~/.hermes/.env
```

Example:

```bash
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrSTUvwxYZ
TELEGRAM_ALLOWED_USERS=123456789
TELEGRAM_HOME_CHANNEL=123456789
TELEGRAM_HOME_CHANNEL_NAME=General
```

`TELEGRAM_ALLOWED_USERS` is a comma-separated list of numeric Telegram user IDs. Get your ID from `@userinfobot`.

`TELEGRAM_HOME_CHANNEL` is the delivery target. For a DM with the bot, it is usually your Telegram user ID. For groups, it is usually a negative chat ID like `-1001234567890`.

Restart the gateway after edits:

```bash
systemctl --user restart agentyard-gateway.service
```

Alternatively, configure the bot token and allowed users, restart the gateway, then send `/sethome` in the Telegram chat you want to use.

## Operations

Run these as `minder` from `~/agentyard`.

List agents:

```bash
scripts/list-agents
```

Show service status:

```bash
scripts/status
```

Update one agent:

```bash
scripts/update-agent hermy
```

Update all agents:

```bash
scripts/update-agents
```

Delete an agent and its Linux user:

```bash
scripts/delete-agent hermy
```

View logs for one agent:

```bash
sudo /usr/local/sbin/agentyard-user run-as hermy journalctl --user -u agentyard-webui.service -f
sudo /usr/local/sbin/agentyard-user run-as hermy journalctl --user -u agentyard-gateway.service -f
```

## Update Model

`scripts/update-agent <agent>` runs the update inside that agent's Linux user:

- `hermes update`
- `git pull --ff-only` in `~/hermes-webui`
- rebuilds/updates the WebUI virtualenv from `requirements.txt`
- restarts `agentyard-gateway.service`
- restarts `agentyard-webui.service`

`scripts/update-agents` runs the same flow sequentially for every registered agent.

## Passwords And Users

Agent users are service accounts:

- password is locked
- no sudo privileges
- no SSH keys are created
- services run with `systemd --user`
- secrets remain inside that user's home directory

The `minder` user is also non-root. It can only run the root-owned Agentyard helper through sudo. That helper creates/deletes agent users, enables lingering, and runs commands as agent users.

## Security Notes

- Do not run Agentyard daemons as root.
- Do not put Cloudflare credentials in agent user accounts.
- Do not put Hermes/OpenAI/Telegram credentials in the `minder` account.
- Use Cloudflare Access as the public browser authentication layer.
- Hermes profiles and Linux users isolate state and files, but agents still have full access to their own user account.
