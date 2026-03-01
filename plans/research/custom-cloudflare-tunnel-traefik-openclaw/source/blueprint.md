Cloudflare Tunnel (`cloudflared`) → Traefik (reverse proxy) → Docker apps, using wildcard subdomains on Cloudflare.

Additionally:
- Expose Traefik dashboard at `https://traefik.<APPS_DOMAIN>` (protected).
- Expose OpenClaw Gateway UI at `https://<BOT_NAME>.<APPS_DOMAIN>` (protected + OpenClaw reverse-proxy safe config).
- Use a global apps docker compose file that OpenClaw (the AI agent) must update whenever it creates a new app.
- Use Cloudflare APIs to ensure DNS is correct (prefer wildcard; fallback to per-subdomain record creation).
- After every deploy, send Joseph a deployment report through OpenClaw configured channels (fallback: print report to stdout).

Core constraints
1. No inbound public ports are required for serving apps (Cloudflare Tunnel is outbound).
2. Do not publish app ports to `0.0.0.0`. Only Traefik and cloudflared run on the internal Docker network.
3. Everything lives under `/opt/openclaw/`.
4. Use a dedicated Linux user `openclaw`.
5. Use one shared Docker network `openclaw-edge` with static IPs so OpenClaw can safely set `gateway.trustedProxies`.

# 0) Required inputs (do NOT guess)
Set these placeholders explicitly before executing automation. Fail if missing.
- `DOMAIN="<root domain>"`
- `APPS_DOMAIN="<apps base domain>"`
- `BOT_NAME="<bot subdomain name>"`
- `TUNNEL_UUID="<cloudflare tunnel uuid>"`
- `CF_ZONE_ID="<cloudflare zone id for DOMAIN>"`
- `CF_API_TOKEN="<token with DNS edit permissions for CF_ZONE_ID>"`
- `REPORT_CHANNEL="<whatsapp|telegram|discord|slack|...>"` (or empty)
- `REPORT_TARGET="<target id>"`

Domain layout choice
Option A (recommended):
- `APPS_DOMAIN="${DOMAIN}"`
- `https://myapp.${DOMAIN}`
- `https://traefik.${DOMAIN}`
- `https://${BOT_NAME}.${DOMAIN}`

Option B:
- `APPS_DOMAIN="apps.${DOMAIN}"`
- `https://myapp.apps.${DOMAIN}`
- `https://traefik.apps.${DOMAIN}`
- `https://${BOT_NAME}.apps.${DOMAIN}`

# 1) Base OS prep + packages
## 1.1 Create user + folders
```bash
sudo adduser --disabled-password --gecos "" openclaw || true
sudo usermod -aG sudo openclaw
sudo mkdir -p /opt/openclaw/{edge,apps,bin,secrets,workspace,openclaw/{config,workspace}}
sudo chown -R openclaw:openclaw /opt/openclaw
```

## 1.2 Install Docker Engine + tools
Install Docker Engine + Compose v2 plugin from Docker official repo.
Also install: `jq`, `apache2-utils`, `python3`, `python3-venv`.

# 2) Docker network
```bash
docker network rm openclaw-edge 2>/dev/null || true
docker network create --subnet 172.30.0.0/24 openclaw-edge
```
Reserved IPs:
- Traefik: `172.30.0.2`
- cloudflared: `172.30.0.3`
- OpenClaw gateway: `172.30.0.10`
Reserved hostnames:
- `traefik`
- `${BOT_NAME}`

# 3) Cloudflare DNS automation
Create scripts:
- `/opt/openclaw/bin/cf_dns_ensure_wildcard.sh`
- `/opt/openclaw/bin/cf_dns_upsert_subdomain.sh`

Desired wildcard:
- `*.${APPS_DOMAIN} -> ${TUNNEL_UUID}.cfargotunnel.com` (proxied=true)

# 4) Edge stack: Traefik + cloudflared
Files:
- `/opt/openclaw/edge/traefik/traefik.yml`
- `/opt/openclaw/secrets/traefik_dashboard_users.env`
- `/opt/openclaw/edge/cloudflared/config.yml`
- `/opt/openclaw/edge/docker-compose.yml`

Expose dashboard:
- `https://traefik.${APPS_DOMAIN}/dashboard/` with basic auth.

# 5) OpenClaw runtime at https://${BOT_NAME}.${APPS_DOMAIN}
- Build `openclaw:local` from source at `/opt/openclaw/openclaw-src`
- Use compose at `/opt/openclaw/openclaw/docker-compose.yml`
- Services:
  - `openclaw-gateway` (internal, routed by Traefik)
  - `openclaw-cli` (admin CLI operations)
- No public port publishing.

OpenClaw config requirements:
- `gateway.trustedProxies=["172.30.0.2"]`
- `gateway.allowRealIpFallback=false`
- `gateway.controlUi.allowedOrigins=["https://${BOT_NAME}.${APPS_DOMAIN}"]`
- `gateway.auth.mode="password"`
- hooks `bootstrap-extra-files` includes `policies/deploy/AGENTS.md`

# 6) Global apps compose
Create `/opt/openclaw/apps/docker-compose.yml` skeleton with `services: {}` and external `openclaw-edge` network.
All app services should be appended here.

# 7) App register/deploy helpers
Create:
- `/opt/openclaw/bin/register_app.py` (ruamel.yaml edits global compose)
- `/opt/openclaw/bin/deploy_app.sh` (register + DNS ensure + build + up + basic health output)

# 8) Reporting helper
Create `/opt/openclaw/bin/report.sh`.
Send via `docker compose run --rm openclaw-cli message send ...`.
Fallback to stdout if `REPORT_TARGET` missing.

# 9) OpenClaw workspace policy injection
Create `/opt/openclaw/openclaw/workspace/policies/deploy/AGENTS.md` with mandatory rules:
- reserved names
- global apps compose usage
- no published ports
- required deployment reporting

# 10) systemd services
Create and enable:
- `/etc/systemd/system/openclaw-edge.service`
- `/etc/systemd/system/openclaw-gateway.service`
Optional: `openclaw-apps.service`.

# 11) Validation checklist
Must validate:
1. wildcard DNS
2. edge stack health
3. traefik dashboard reachable/auth
4. OpenClaw UI reachable
5. demo app deploy (`whoami`)

# 12) Final report to Joseph
Report must include:
- APPS_DOMAIN layout + SSL implications
- tunnel UUID + wildcard status
- URLs (OpenClaw, Traefik, demo app)
- compose ps outputs
- warnings/issues + resolutions

Send via:
```bash
/opt/openclaw/bin/report.sh "OpenClaw Infra Setup Complete" "<full report body>"
```
If report target unset, print to stdout.
