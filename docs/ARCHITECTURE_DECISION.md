# Architecture Decision: Bash-First OpenClaw Edge Toolkit

## 1. Title + Metadata
- Decision: Canonical architecture and implementation contract for `infra-ubuntu-2404-openclaw` (Bash-first)
- Status: Accepted
- Date: 2026-03-01
- Scope: Ubuntu Server 24.04 LTS (noble), secure OpenClaw host provisioning, Cloudflare Tunnel edge routing, global app deployment workflow
- Canonical Source of Truth: This document
- Supporting Inputs:
  - `plans/APPROVED_BASE_PLAN.md`
  - `plans/research/*/analysis.md`
  - `plans/research/custom-cloudflare-tunnel-traefik-openclaw/source/blueprint.md`

## 2. Problem + Goals
This project started with mixed community scripts and an older Ansible-oriented history. Existing approaches were useful but inconsistent on security defaults, idempotence, and edge architecture.

Primary problems to solve:
1. Many scripts optimize for quick setup, but not for strict secure defaults or repeatable long-term operations.
2. SSH hardening, user model, firewall behavior, and OpenClaw exposure varied across sources.
3. Reverse proxy + tunnel architecture was often optional or loosely defined.
4. App deployment flow for AI-created apps lacked a single authoritative compose and policy enforcement model.

Goals:
1. Define one decision-complete architecture with no unresolved implementation choices.
2. Lock non-negotiable security defaults.
3. Standardize Cloudflare Tunnel -> Traefik -> Docker app routing under one global model.
4. Define required interfaces for Bash implementation modules/scripts.
5. Preserve and explicitly map all analyzed research inputs (no omissions).

Success criteria:
1. A new implementer can build step #1 onward without making architecture decisions.
2. Security defaults are consistent and explicit across host, edge, and OpenClaw runtime.
3. Every research source has explicit Adopt/Modify/Reject outcomes.

## 3. Research Coverage Matrix (mandatory)

| Source | Strengths adopted | Risks rejected | Modifications required |
|---|---|---|---|
| `rarecloud-openclaw-setup` | Loopback gateway/token model; baseline hardening intent; helper script ergonomics; clear post-install UX | Root SSH enabled; default SSH port mismatch; root-centric ops; one-shot convergence model | Keep loopback/token and service bootstrap; enforce SSH `1773` + key-only + no root login; adopt modular/idempotent Bash design |
| `locryns-vm-linux-hardening-setup` | Strong preflight validation; SSH syntax checks/rollback; key-only/root-deny pattern; DRY_RUN concept; service hardening flags | Always-on public backdoor sshd; Tailscale-only SSH lock as baseline; permissive NOPASSWD defaults | Keep validation/rollback discipline; keep optional DRY_RUN; make emergency access explicit opt-in only; align with our ingress architecture |
| `stfurkan-claw-easy-setup` | `sshd_config.d` drop-in strategy; SSH-before-firewall ordering; practical baseline controls; systemd linger handling | Password-auth left enabled by default; interactive-first path; forced reboot; root-key copy behavior | Keep drop-in and guard patterns; enforce key-only SSH baseline from first run; make reboot optional and explicit |
| `mundofacu-openclaw-vm-setup` | VM isolation mindset; temporary elevation then revoke; egress containment concept; swap bootstrap option | Missing host access hardening; manual-heavy post-install; fixed user assumptions | Keep optional isolated-egress profile and swap flags; integrate with full host baseline and non-interactive execution |
| `eyal050-openclaw-remote-install` | Strong phased orchestration; diagnostics/logging quality; workspace preservation; remote orchestration mechanics | `allowInsecureAuth` default; LAN bind exposure posture; port 22/open gateway firewall defaults; password SSH mode emphasis | Keep phased architecture and diagnostics patterns; enforce secure defaults (loopback-first, strict proxy trust, key-first remote auth); keep helpers as optional modules |
| `phucmpham-deploy-openclaw` | Safety-gated SSH hardening; rollback stack and resume state; interactive UX quality; strong shell test culture (BATS) | Interactive-only baseline; root key login still allowed (`prohibit-password`); implicit 80/443 openings | Keep state/rollback and shell testing patterns; provide non-interactive default mode; enforce no root SSH login and port `1773` baseline |
| `mortalezz-openclaw` | Hetzner-specific dbus/user-systemd handling insight; reboot-resume pattern; loopback bind posture | Permanent NOPASSWD for service user; SSH left on 22; incomplete SSH/fail2ban/unattended baseline; interactive password dependence | Keep platform-profile handling and user-systemd readiness checks; enforce full host baseline and least-privilege service model |
| `custom-cloudflare-tunnel-traefik-openclaw` | Canonical edge architecture; global apps compose ownership; static proxy network contract; DNS wildcard-first automation; deployment reporting; policy injection model | None rejected at architecture level; this is the chosen blueprint with controlled adjustments | Make workspace policy injection mandatory; apply locked security baseline; lock dual-user model (`hendaz` admin, `openclaw` runtime) |

## 4. Final Architecture
### 4.1 Topology
1. Cloudflare Tunnel (`cloudflared`) provides outbound-only ingress path.
2. Traefik is the single reverse proxy on internal Docker network.
3. OpenClaw Gateway and all apps are reachable through Traefik host-based routes.
4. No application container publishes service ports publicly.

### 4.2 Stack ownership
1. Edge stack: `/opt/openclaw/edge/docker-compose.yml`
   - Contains only shared edge services (`traefik`, `cloudflared`).
   - Immutable for app onboarding flows.
2. OpenClaw runtime stack: `/opt/openclaw/openclaw/docker-compose.yml`
   - Contains gateway + CLI/admin service.
3. Global apps stack: `/opt/openclaw/apps/docker-compose.yml`
   - Single mutable registry for all AI-created apps.
   - Updated only through sanctioned helper scripts.

### 4.3 Exposure model
1. Traefik dashboard: `https://traefik.<APPS_DOMAIN>` (must be protected).
2. OpenClaw UI: `https://<BOT_NAME>.<APPS_DOMAIN>`.
3. App URL pattern: `https://<appName>.<APPS_DOMAIN>`.
4. Cloudflare DNS: wildcard preferred; per-host fallback when wildcard cannot be ensured.

## 5. Security Baseline (non-negotiable)
1. SSH port is `1773`.
2. `PermitRootLogin no`.
3. `PasswordAuthentication no`.
4. SSH access is key-only for admin user.
5. `fail2ban` enabled for SSH.
6. `unattended-upgrades` enabled for security updates.
7. UFW baseline deny incoming/allow outgoing with only explicitly required rules.
8. No app service may publish `ports:` to `0.0.0.0`.

Locked user model:
1. `hendaz` is the admin SSH/sudo operator user.
2. `openclaw` is the non-privileged runtime/service user.
3. Service workloads run as `openclaw` (or container user), not as `hendaz`.

## 6. Network + Proxy Contract
1. Shared Docker network name: `openclaw-edge`.
2. Subnet: `172.30.0.0/24`.
3. Reserved static IPs:
   - Traefik: `172.30.0.2`
   - cloudflared: `172.30.0.3`
   - OpenClaw gateway: `172.30.0.10`
4. Reserved hostnames/app names:
   - `traefik`
   - `${BOT_NAME}`
5. OpenClaw proxy safety:
   - `gateway.trustedProxies` must include `172.30.0.2`.
   - `gateway.allowRealIpFallback` must be `false`.
   - `gateway.controlUi.allowedOrigins` must include `https://${BOT_NAME}.${APPS_DOMAIN}`.
6. DNS strategy:
   - First try wildcard CNAME: `*.${APPS_DOMAIN}` -> `${TUNNEL_UUID}.cfargotunnel.com` (proxied).
   - Fallback to per-subdomain CNAME upsert if wildcard ensure fails.

## 7. Filesystem + Ownership Contract
Root layout under `/opt/openclaw`:
1. `edge/` shared ingress stack files.
2. `apps/` global compose + per-app build contexts.
3. `bin/` operational helper scripts.
4. `secrets/` local secret files with strict permissions.
5. `workspace/` general working area if needed.
6. `openclaw/config` OpenClaw state/config mount source.
7. `openclaw/workspace` OpenClaw agent workspace mount source.

Ownership and permission expectations:
1. `/opt/openclaw` content owned by `openclaw:openclaw` unless root-owned system unit files require otherwise.
2. Secrets files should be least-privilege readable (typically mode `600`).
3. Systemd unit files live under `/etc/systemd/system/` and are root-managed.
4. Admin operations are performed via `hendaz` with sudo.

## 8. Public Interfaces / Contracts
### 8.1 Required environment contract
Required variables (must fail-fast if missing where applicable):
1. `DOMAIN`
2. `APPS_DOMAIN`
3. `BOT_NAME`
4. `TUNNEL_UUID`
5. `CF_ZONE_ID`
6. `CF_API_TOKEN`

Reporting variables:
1. `REPORT_OWNER_NAME` (optional; defaults to `Joseph`)
2. `REPORT_CHANNEL` (optional)
3. `REPORT_TARGET` (optional, but required for channel delivery)

Additional OpenClaw runtime secrets/config:
1. `OPENCLAW_GATEWAY_TOKEN`
2. `OPENCLAW_GATEWAY_PASSWORD`

Default assumptions:
1. `APPS_DOMAIN=DOMAIN` (Option A) unless explicitly overridden.
2. Cloudflare API token is primary DNS automation method.

### 8.2 Script interface contracts
1. `cf_dns_ensure_wildcard.sh`
   - Inputs: `CF_ZONE_ID`, `CF_API_TOKEN`, `APPS_DOMAIN`, `TUNNEL_UUID`
   - Output: ensures wildcard CNAME exists; idempotent no-op if present.
2. `cf_dns_upsert_subdomain.sh`
   - Inputs: `CF_ZONE_ID`, `CF_API_TOKEN`, `HOSTNAME`, `TUNNEL_UUID`
   - Output: creates/updates one CNAME record.
3. `register_app.py`
   - Inputs: `APP_NAME`, `APP_PORT`, `APPS_DOMAIN` (+ optional `BOT_NAME` reserved-name guard)
   - Output: deterministic update of `/opt/openclaw/apps/docker-compose.yml`.
4. `deploy_app.sh <appName> <internalPort>`
   - Behavior: register app, ensure DNS (wildcard preferred), build/start app, emit deployed URL/status.
5. `report.sh <title> <body>`
   - Behavior: send via OpenClaw channel when reporting vars are set; otherwise print to stdout.

### 8.3 Systemd units expected
1. `openclaw-edge.service`
   - Controls edge stack (`/opt/openclaw/edge`).
2. `openclaw-gateway.service`
   - Controls OpenClaw runtime stack (`/opt/openclaw/openclaw`).
3. Optional: `openclaw-apps.service`
   - Ensures global apps compose is up on boot.

Compose ownership contract:
1. Edge compose is immutable for per-app onboarding.
2. Apps compose is the single mutable app registry.

## 9. Mandatory OpenClaw Policy Injection
This is mandatory, not optional.

Required hook behavior:
1. OpenClaw config must enable `hooks.internal.entries.bootstrap-extra-files`.
2. Hook paths must include deployment policy file in workspace context.

Required policy file contract:
1. Path: `/opt/openclaw/openclaw/workspace/policies/deploy/AGENTS.md`.
2. Required rules include:
   - Reserved app names (`traefik`, `${BOT_NAME}`).
   - Must update global apps compose via helper scripts.
   - Must not publish ports directly.
   - Must deploy through sanctioned flow and validate route health.
   - Must send deployment report to configured owner `${REPORT_OWNER_NAME}` (or stdout fallback when channel not configured).

## 10. Reporting Contract
Deployment report owner: `${REPORT_OWNER_NAME}`.

Report schema requirements:
1. App name
2. URL
3. Internal port
4. `docker compose ps` result snippet
5. Health probe result
6. Last logs on error path

Delivery behavior:
1. If `REPORT_TARGET` is set, send through OpenClaw CLI `message send` flow.
2. If `REPORT_CHANNEL` is set, use that channel explicitly.
3. If reporting target is missing, print full report to stdout and treat as fallback success.

## 11. Acceptance Criteria
### 11.1 Architecture consistency checks
1. Final topology is Cloudflare Tunnel -> Traefik -> internal app services.
2. Edge, OpenClaw, and global apps compose ownership boundaries are explicit and non-conflicting.
3. No unresolved decisions remain in interfaces and contracts.

### 11.2 Security default consistency checks
1. SSH defaults are exactly: port `1773`, no root login, key-only auth.
2. Dual-user model explicitly states `hendaz` admin and `openclaw` runtime separation.
3. fail2ban and unattended-upgrades are baseline requirements.
4. No app `ports` publishing is allowed under standard flow.

### 11.3 Research coverage completeness checks
1. All eight research sources are present in the matrix.
2. Each row has explicit Adopt/Reject/Modify outcomes.
3. Mandatory workspace policy injection is represented in final architecture and contracts.

## 12. Non-goals + Deferred Items
Non-goals for this decision artifact:
1. No script/code implementation in this step.
2. No migration of legacy historical docs into a single file.
3. No immediate CI or Molecule scenario rewiring in this step.

Deferred items (for implementation phases):
1. Bash module implementation (`scripts/install.sh`, `scripts/lib/*.sh`).
2. Concrete test harness updates and end-to-end validation automation.
3. Optional advanced profiles (isolated-egress modes, break-glass access mode, etc.).

## 13. Change Control
1. This file is canonical architecture source of truth.
2. Architecture changes require updating this file first, then implementation.
3. Proposed updates should include:
   - changed decision
   - rationale
   - impact on interfaces/tests
4. Previous research bundles in `plans/research/*/source/` remain immutable historical references.
