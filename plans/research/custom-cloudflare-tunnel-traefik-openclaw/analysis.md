# Research Note: Custom Blueprint (Preferred Target Architecture)

Reference source:
- `plans/research/custom-cloudflare-tunnel-traefik-openclaw/source/blueprint.md`

Status:
- This is not a third-party reference; it is the preferred design direction to implement.

## Architecture Summary

Primary topology:
- Cloudflare Tunnel (`cloudflared`) -> Traefik -> app containers
- No direct inbound public app ports
- Shared Docker network: `openclaw-edge` (static IPs)
- Root path convention: `/opt/openclaw/*`

Core exposure model:
1. Traefik dashboard at `https://traefik.<APPS_DOMAIN>` with auth.
2. OpenClaw UI at `https://<BOT_NAME>.<APPS_DOMAIN>` with reverse-proxy-safe OpenClaw config.
3. App routing via wildcard subdomains and Traefik labels from one global apps compose.

## Why This Is Strong

1. Strong edge isolation model.
- Tunnel is outbound-only, reducing internet-facing attack surface.

2. Centralized ingress control.
- One Traefik layer and one global apps compose reduce routing drift.

3. OpenClaw safety alignment.
- Explicit `trustedProxies`, `allowedOrigins`, and policy injection for deployment behavior.

4. Operational consistency.
- Shared helper scripts for DNS, app registration, deployment, and reporting.

5. Good automation surface.
- Explicit environment contracts and fail-fast requirements.

## Risks / Decisions to Handle Explicitly

1. SSL model for nested subdomains.
- Option A (`APPS_DOMAIN=DOMAIN`) is safest with standard Cloudflare cert coverage.
- Option B requires explicit certificate/zone strategy.

2. Static IP coupling.
- Requires stable subnet management and reserved-name enforcement.

3. Secrets management.
- `.env` and API tokens must be handled with strict permissions and optional vault/encrypted flow.

4. Reporting coupling to OpenClaw channels.
- Need robust fallback-to-stdout if channels are not configured.

5. Compose ownership model.
- Global apps compose is a single source of truth; automated YAML edits must be deterministic and safe.

## Keep / Implement Exactly

1. `/opt/openclaw` directory model and dedicated `openclaw` user.
2. `openclaw-edge` network with static IP assignments.
3. Cloudflare wildcard-first DNS automation + single-host fallback script.
4. Global edge stack (`traefik` + `cloudflared`) as stable always-on stack.
5. Global apps compose and script-based app registration/deployment.
6. OpenClaw policy injection to force compliant app deployment behavior.
7. Deployment report workflow to Joseph with channel fallback.

## Adjustments for Our Existing Security Baseline

To remain consistent with our approved base plan:
1. Keep SSH baseline hardening (`1773`, no root SSH login, key-only auth).
2. Ensure no app services publish ports publicly.
3. Keep fail2ban/unattended-upgrades baseline around this architecture.
4. Preserve idempotent, rerunnable shell steps for each component.

## Mapping to `plans/APPROVED_BASE_PLAN.md`

This blueprint directly covers:
1. Step 5 (reverse-proxy stack integration): Cloudflare + Traefik + tunnel model.
2. Step 4 (OpenClaw core): secure routed OpenClaw runtime and CLI/reporting pattern.
3. Step 6 (operator UX): reporting, policy injection, deterministic app deployment workflow.

It also informs implementation details for:
1. Step 1 (framework modules): add `edge.sh`, `dns.sh`, `apps.sh`, `report.sh`.
2. Step 8 (docs/runbook): explicit domain-layout/SSL guidance and validation checklist.

## Recommended Next Implementation Slice

Implement first in this order:
1. Config contract + validation for required vars (`DOMAIN`, `APPS_DOMAIN`, `BOT_NAME`, `TUNNEL_UUID`, `CF_ZONE_ID`, `CF_API_TOKEN`, optional report vars).
2. Edge foundation (`openclaw-edge` network + Traefik + cloudflared compose + systemd).
3. OpenClaw docker runtime and proxy-safe config.
4. Apps register/deploy helpers + DNS scripts.
5. Report helper and final validation/report generation.
