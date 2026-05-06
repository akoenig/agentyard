# Agentyard

Agentyard makes it easy to create and operate isolated [Hermes Agent](https://hermes-agent.nousresearch.com/) + [Hermes WebUI](https://github.com/nesquena/hermes-webui) agents on one Linux host.

## Features

- Create agents as isolated non-root Linux users with their own Hermes Agent, Hermes WebUI, credentials, memory, cron jobs, and workspace.
- Run WebUI without opening public inbound server ports; Cloudflare Tunnel connects outbound to Cloudflare and forwards traffic to localhost.
- Protect every agent hostname with Cloudflare Access SSO, including Google Login, GitHub Login, Microsoft Entra ID, Okta, and other supported identity providers.
- Keep all long-running daemons non-root: Cloudflare Tunnel runs as `minder`, and each agent's WebUI and gateway run as that agent user.
- Bootstrap a fresh Ubuntu/Debian host with one public `curl | sudo sh` installer.
- Avoid Docker entirely while still getting repeatable bootstrap, create, update, delete, status, and list commands.

The runtime model is intentionally simple:

- `minder` is the non-root control-plane user.
- each agent is its own non-root Linux user named after the agent.
- Cloudflare Tunnel runs as the non-root `minder` user.
- [Hermes Agent](https://hermes-agent.nousresearch.com/), [Hermes WebUI](https://github.com/nesquena/hermes-webui), credentials, memory, cron jobs, and workspace files live inside each agent user's home directory.
- no Docker is used.

## Architecture

```text
Browser
  -> https://<agent-name>.example.com
  -> Cloudflare Access
  -> Cloudflare Tunnel owned by minder
  -> http://127.0.0.1:8787
  -> agentyard-webui.service owned by <agent-name>
```

Users and services:

```text
minder
  agentyard-cloudflared.service
  ~/agentyard
  ~/agentyard/agents/<agent-name>/agent.env

<agent-name>
  agentyard-webui.service
  hermes-gateway.service
  ~/.hermes
  ~/hermes-webui
  ~/workspace
```

Root is only needed for one-time control-plane bootstrap and narrow OS account operations through `/usr/local/sbin/agentyard-user`. No long-running daemon runs as root.

## Requirements

You need:

- an Ubuntu or Debian host with `systemd`
- root or sudo access for the initial bootstrap only
- a Cloudflare account with a Tunnel and Access available
- a Cloudflare Access SSO identity provider, for example Google, GitHub, Microsoft Entra ID, Okta, or another supported provider
- a domain routed through Cloudflare, for example `example.com`
- credentials or a subscription for the Hermes provider you want to use

The server does not need to be publicly exposed. No inbound firewall ports need to be opened for WebUI because Cloudflare Tunnel makes an outbound connection from the host to Cloudflare and forwards traffic to localhost.

## Step 1: Bootstrap The Control Plane

On a fresh host, run the public bootstrap installer:

```bash
curl -fsSL https://raw.githubusercontent.com/akoenig/agentyard/main/install.sh | sudo sh
```

This clones Agentyard into `~minder/agentyard`, runs the control-plane bootstrap, and installs the global `agentyard` command at `/usr/local/bin/agentyard`.

If you already cloned the repository manually, you can run the bootstrap from the clone instead:

```bash
sudo ./agentyard install-control-plane
```

This creates:

- required system packages and tools when missing: `git`, `curl`, `python3`, `python3-venv`, `python3-dev`, `sudo`, `unattended-upgrades`, `ripgrep`, `ffmpeg`, `build-essential`, `libffi-dev`, and `cloudflared`
- Linux user `minder`
- system group `agentyard-agents`
- root-owned helper `/usr/local/sbin/agentyard-user`
- root-owned global CLI wrapper `/usr/local/bin/agentyard`, which executes Agentyard commands as `minder`
- sudoers rule allowing `minder` to run only that helper without a password
- lingering for `minder`, so its user services can run after logout

## Step 2: Initialize Agentyard

Run the interactive initializer after the bootstrap installer completes:

```bash
agentyard init
```

The installer creates `.env` from `.env.example` if needed and asks for missing required values.

You will be prompted for:

- `AGENT_BASE_DOMAIN`, for example `example.com`
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
agentyard create <agent-name>
```

This creates Linux user `<agent-name>`, locks its password, enables lingering, installs Hermes Agent and Hermes WebUI into that user's home directory, and ensures these user services exist:

```text
~<agent-name>/.config/systemd/user/agentyard-webui.service
~<agent-name>/.config/systemd/user/hermes-gateway.service
```

The script configures the agent's default workspace:

```yaml
terminal:
  backend: local
  cwd: /home/<agent-name>/workspace
```

During creation, Agentyard starts `hermes setup` as the `<agent-name>` user. Use the Hermes Agent wizard to choose and authenticate the provider and messaging platforms for that agent. If the wizard installs the Hermes gateway service, Agentyard uses it. If it does not, Agentyard runs `hermes gateway install` and starts `hermes-gateway.service` for the agent.

## Step 4: Configure Cloudflare SSO

Cloudflare Access SSO is required because WebUI is exposed through Cloudflare, not directly through public server ports.

Configure an identity provider in Cloudflare Zero Trust:

1. Open the Cloudflare dashboard at `https://dash.cloudflare.com/`.
2. Select **Zero Trust** for the account that owns the tunnel and Access applications.
3. Go to **Integrations** -> **Identity providers**.
4. Select **Add new identity provider**.
5. Choose Google, GitHub, Microsoft Entra ID, Okta, or another provider your organization uses.
6. Complete the provider-specific OAuth/SAML setup and save it.
7. Use the provider **Test** action to confirm SSO works before exposing an agent hostname.

For Google SSO, create a Google OAuth app with application type `Web application`, then use the Cloudflare Access team domain values:

```text
Authorized JavaScript origin: https://<your-team-name>.cloudflareaccess.com
Authorized redirect URI:      https://<your-team-name>.cloudflareaccess.com/cdn-cgi/access/callback
```

Enable PKCE if Cloudflare offers that option for the provider.

## Step 5: Configure Cloudflare Route

After agent creation, the script prints the Cloudflare route to add:

```text
Hostname: <agent-name>.example.com
Service:  http://127.0.0.1:8787
```

Create or update a remotely-managed Cloudflare Tunnel route:

1. In Cloudflare Zero Trust, go to **Networks** -> **Connectors** -> **Cloudflare Tunnels**.
2. Select your tunnel, or select **Create a tunnel** if you do not have one yet.
3. If creating a tunnel, choose **Cloudflared**, name the tunnel, save it, and copy the tunnel token into Agentyard when `agentyard init` asks for `CLOUDFLARE_TUNNEL_TOKEN`.
4. In the tunnel, go to **Published applications**.
5. Add a public hostname for the agent.
6. Set the hostname to `<agent-name>.example.com`.
7. Set **Service** type to `HTTP` and URL to `127.0.0.1:8787`.
8. Save the route.

Then protect the hostname with a Cloudflare Access application that uses your configured SSO provider:

1. In Cloudflare Zero Trust, go to **Access controls** -> **Applications**.
2. Select **Add an application**.
3. Select **Self-hosted**.
4. Enter a name such as `<agent-name>`.
5. Select **Add public hostname** and set the domain to `<agent-name>.example.com`.
6. Add an Allow policy for the assigned user or group.
7. Select the identity provider you configured in Step 4.
8. Enable **Instant Auth** if this application should always use one provider directly.
9. Save the application.

Recommended Access policy:

```text
Application: <agent-name>.example.com
Policy: Allow
Include: Emails
Email: assigned-user@example.com
```

Create one Access application per agent hostname. Avoid broad `Everyone`, domain-wide, or organization-wide allow policies unless the agent should be shared by that full group.

Each WebUI listens only on `127.0.0.1`, so the host does not expose WebUI ports directly to the public network. Cloudflare Tunnel is outbound-only, so no public port opening is required.

## Step 6: Open WebUI

Open:

```text
https://<agent-name>.example.com
```

Cloudflare Access authenticates the browser. Hermes WebUI then talks to the Hermes runtime owned by the `<agent-name>` Linux user.

## Operations

Run these from any shell. The global wrapper executes Agentyard as `minder`.

List agents:

```bash
agentyard list
```

Show service status:

```bash
agentyard status
```

Update one agent:

```bash
agentyard update <agent-name>
```

Update all agents:

```bash
agentyard update-all
```

Delete an agent and its Linux user:

```bash
agentyard delete <agent-name>
```

View logs for one agent:

```bash
sudo /usr/local/sbin/agentyard-user run-as <agent-name> journalctl --user -u agentyard-webui.service -f
sudo /usr/local/sbin/agentyard-user run-as <agent-name> journalctl --user -u hermes-gateway.service -f
```

## Update Model

`agentyard update <agent>` runs the update inside that agent's Linux user:

- `hermes update`
- `git pull --ff-only` in `~/hermes-webui`
- rebuilds/updates the WebUI virtualenv from `requirements.txt`
- ensures lingering and `hermes-gateway.service`
- restarts `agentyard-webui.service`

`agentyard update-all` runs the same flow sequentially for every registered agent.

## Passwords And Users

Agent users are service accounts:

- password is locked
- no sudo privileges
- no SSH keys are created
- services run with `systemd --user`
- secrets remain inside that user's home directory

The `minder` user is also non-root. It can only run the root-owned Agentyard helper through sudo. That helper creates/deletes agent users, enables lingering, and runs commands as agent users.
