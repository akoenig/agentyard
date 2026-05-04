# Frontend

OpenWebUI deployment for publishing a chat frontend through Cloudflare Tunnel without exposing host ports.

## Layout

```text
Browser
  -> https://chat.example.com
  -> Cloudflare Tunnel
  -> cloudflared container
  -> open-webui:8080

OpenWebUI
  -> https://<agent>-hermes-api.<domain>/v1
```

## Setup

1. Create the frontend environment file.

```bash
cp frontend/.env.example frontend/.env
chmod go-rwx frontend/.env
```

2. Edit `frontend/.env`.

Required values:

- `OPENWEBUI_PUBLIC_URL`, for example `https://chat.something.com`
- `CLOUDFLARE_TUNNEL_TOKEN`

3. Start OpenWebUI and the tunnel.

```bash
docker compose --env-file frontend/.env -f frontend/compose.yaml up -d
```

No `ports:` are published by this Compose file. Cloudflare reaches OpenWebUI over the Docker network through the `cloudflared` container.

## Cloudflare

Create a tunnel public hostname:

```text
Hostname: chat.something.com
Service:  http://open-webui:8080
```

Use Cloudflare Access initially, even if OpenWebUI Google Auth is enabled. Access blocks unauthorized traffic before it reaches OpenWebUI.

## Notes

Add Hermes or LiteLLM connections in OpenWebUI's admin settings. For Hermes, use the agent's OpenAI-compatible endpoint with `/v1`, for example `https://hermy-hermes-api.workspace.openformation.net/v1`, and the matching `HERMES_<AGENT>_API_SERVER_KEY`.
