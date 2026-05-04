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
chmod go-rwx frontend/.env*
```

2. Edit `frontend/.env`.

Required values:

- `OPENWEBUI_PUBLIC_URL`, for example `https://chat.something.com`
- `OPENWEBUI_SECRET_KEY`, generated with `openssl rand -hex 32`
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
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

## Google Auth

OpenWebUI is wired for Google OAuth and defaults the hosted-domain hint to `openformation.io`:

```text
GOOGLE_OAUTH_AUTHORIZE_PARAMS={"hd":"openformation.io"}
```

Set up the Google OAuth client:

1. Open Google Cloud Console and select the OpenFormation organization/project that owns the OAuth client.
2. Configure the OAuth consent screen for the OpenFormation Google Workspace. Use an internal app if available for the organization.
3. Create an OAuth client ID with application type `Web application`.
4. Add this authorized redirect URI, matching `OPENWEBUI_PUBLIC_URL` exactly:

```text
https://chat.something.com/oauth/google/callback
```

5. Copy the client ID and secret into `frontend/.env`:

```bash
GOOGLE_CLIENT_ID=<client-id>.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=<client-secret>
```

6. Keep these OAuth settings in `frontend/.env`:

```bash
OPENWEBUI_ENABLE_OAUTH_SIGNUP=true
OPENWEBUI_ENABLE_OAUTH_PERSISTENT_CONFIG=false
OPENWEBUI_OAUTH_MERGE_ACCOUNTS_BY_EMAIL=true
OPENWEBUI_ENABLE_OAUTH_ID_TOKEN_COOKIE=false
OPENID_PROVIDER_URL=https://accounts.google.com/.well-known/openid-configuration
GOOGLE_OAUTH_AUTHORIZE_PARAMS={"hd":"openformation.io"}
```

7. Recreate OpenWebUI after changing OAuth environment variables:

```bash
docker compose --env-file frontend/.env -f frontend/compose.yaml up -d --force-recreate open-webui
```

The Google `hd` parameter is a hosted-domain hint for the Google login flow. Treat Cloudflare Access with an `@openformation.io` email-domain policy or a Google Workspace internal OAuth app as the actual access boundary.

## Notes

Add Hermes or LiteLLM connections in OpenWebUI's admin settings. For Hermes, use the agent's OpenAI-compatible endpoint with `/v1`, for example `https://hermy-hermes-api.workspace.openformation.net/v1`, and the matching `HERMES_<AGENT>_API_SERVER_KEY`.
