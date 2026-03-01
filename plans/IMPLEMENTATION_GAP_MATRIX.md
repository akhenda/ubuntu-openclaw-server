# Implementation Gap Matrix (Plans vs Current Bash Toolkit)

Date: 2026-03-01  
Scope reviewed: `plans/APPROVED_BASE_PLAN.md`, `plans/research/*/analysis.md`, `docs/ARCHITECTURE_DECISION.md`  
Implementation reviewed: `scripts/`, `config/`, `tests/`, `molecule/`, `Makefile`, `README.md`

## 1. Executive Summary

The Bash migration is materially complete for the core architecture:

1. Secure SSH baseline, dual-user model, firewall baseline, Cloudflare Tunnel + Traefik edge, OpenClaw runtime, policy injection, global apps registry, reporting helper, and Molecule-based docker/vagrant validation are implemented.
2. Several items from the approved plan and research synthesis remain partial or missing, including:
   - Tailscale baseline integration (missing, now mandatory requirement)
   - Auto-created `hub.<domain>` / `apps.<domain>` landing service for first app and onward autodiscovery (missing)
   - MOTD status script (missing)
   - Hostname/timezone configuration (missing)
   - Oh-My-Zsh operator QoL (missing)
   - Docker socket proxy hardening (missing)
   - fail2ban/unattended-upgrades explicit service/config management (partial)
   - edge systemd unit (`openclaw-edge.service`) and optional apps systemd unit (missing)

## 2. Approved Base Plan Coverage

| Approved Plan Item | Status | Evidence | Gap |
|---|---|---|---|
| Bash framework (`scripts/install.sh`, modular `scripts/lib/*.sh`, env config) | Implemented | `scripts/install.sh`, `scripts/lib/*.sh`, `config/example.env` | None |
| Access lockdown (`1773`, no root login, no password auth, env/admin key) | Implemented | `scripts/lib/ssh.sh`, `scripts/lib/config.sh`, `scripts/lib/user.sh` | None |
| Baseline security services (fail2ban, unattended, timezone, hostname, firewall) | Partial | `scripts/lib/packages.sh`, `scripts/lib/firewall.sh` | timezone/hostname not implemented; fail2ban/unattended installed but not explicitly configured/enabled |
| OpenClaw core install path + systemd + checks | Partial | `scripts/lib/openclaw.sh`, `scripts/lib/verify.sh` | openclaw-edge systemd missing; health checks are artifact-level, not end-to-end runtime probes |
| Reverse proxy integration (socket proxy + Traefik + Cloudflare) | Partial | `scripts/lib/edge.sh`, `scripts/lib/dns.sh` | socket proxy missing |
| Operator QoL (MOTD + Oh-My-Zsh) | Missing | no `motd` or `oh_my_zsh` phase/module | full feature missing |
| Rewired shell-first tests (docker + vagrant) | Implemented | `molecule/docker/*`, `molecule/vagrant/*`, `Makefile` | None |
| Control surface/docs update | Implemented | `Makefile`, `README.md`, `docs/HANDOVER.md` | None |

## 3. Architecture Decision Contract Coverage

| Architecture Contract | Status | Evidence | Gap |
|---|---|---|---|
| Cloudflare Tunnel -> Traefik -> apps topology | Implemented | `scripts/lib/edge.sh`, `scripts/lib/apps.sh` | None |
| No public app port publishing | Implemented | `scripts/lib/apps.sh` labels-only model, generated policy in `scripts/lib/openclaw.sh` | None |
| `openclaw-edge` network + static IPs | Implemented | `scripts/lib/config.sh`, `scripts/lib/edge.sh` | None |
| Dual-user model (`hendaz`, `openclaw`) | Implemented | `scripts/lib/config.sh`, `scripts/lib/user.sh` | None |
| SSH hardening non-negotiables | Implemented | `scripts/lib/ssh.sh`, `scripts/lib/config.sh` | None |
| DNS wildcard + per-host fallback helper scripts | Implemented | `scripts/lib/dns.sh`, generated helper contracts | None |
| Mandatory policy injection (`bootstrap-extra-files`) | Implemented | `scripts/lib/openclaw.sh` JSON + AGENTS policy rendering | None |
| Reporting contract with fallback | Implemented | `scripts/lib/report.sh` | None |
| Auto hub service creation on first app + app autodiscovery UX | Missing | no hub module/service/hook in `scripts/lib/*`; no hub labels in app registry script | add `hub` service lifecycle, first-app trigger, and discovery metadata contract with per-app URL click-through |
| Expected systemd units (`openclaw-edge`, `openclaw-gateway`, optional apps) | Partial | `scripts/lib/openclaw.sh` manages only gateway unit | edge/apps units missing |
| Baseline fail2ban + unattended-upgrades enabled/configured | Partial | package install in `scripts/lib/packages.sh` | explicit config/service/jail management missing |

## 4. Research Matrix (One-by-One)

| Research Source | Adopted/Implemented | Partial | Missing |
|---|---|---|---|
| `rarecloud-openclaw-setup` | helper-script ergonomics, token auth, security-first structure | loopback binding adapted to reverse-proxy mode (`--bind lan` on internal network) | n/a |
| `locryns-vm-linux-hardening-setup` | DRY_RUN style, validation discipline, SSH syntax validation/rollback | service hardening depth is lighter than source | Tailscale mode, break-glass access profile |
| `stfurkan-claw-easy-setup` | `sshd_config.d` drop-in model, SSH-before-firewall ordering | none | swap option, user-linger ergonomics |
| `mundofacu-openclaw-vm-setup` | least-privilege runtime user model | none | optional swap profile, optional isolated-egress profile |
| `eyal050-openclaw-remote-install` | phased orchestration and log discipline | diagnostics are basic (no dedicated diagnose mode) | remote installer wrapper mode, workspace backup/restore |
| `phucmpham-deploy-openclaw` | shell test culture (phase tests), SSH safety checks | rollback exists for SSH only (not broader stateful resume) | state-file resume workflow, BATS harness |
| `mortalezz-openclaw` | OpenClaw local runtime + systemd handling pattern | none | reboot-resume flow, host-profile-specific dbus/user-systemd checks |
| `custom-cloudflare-tunnel-traefik-openclaw` | edge/app topology, DNS helper contracts, policy injection, reporting helper, global apps compose | edge systemd service and full final validation checklist incomplete | none beyond listed partials |

## 5. Tailscale Requirement (Updated)

Tailscale is currently absent, but is now treated as a mandatory requirement for this project.

Why multiple researched implementations used Tailscale:

1. Private administrative access plane independent from public ingress routing.
2. Reduced exposed SSH surface (private mesh ingress, optional source controls).
3. Strong operational ergonomics for remote ops (`tailscale ssh`, stable identity/IP model).
4. Compatibility with “no public app ports” model while still preserving secure operator reachability.

Second-pass findings:

1. `locryns-vm-linux-hardening-setup` relies on Tailscale as the primary access plane and couples firewall/SSH policy to `tailscale0`.
2. `phucmpham-deploy-openclaw` exposes Tailscale as an operator-selectable security control and documents transition steps.
3. Other sources do not standardize Tailscale, but consistently struggle with secure remote access tradeoffs that Tailscale directly addresses.

Current implementation status:

- No Tailscale config vars in `config/example.env`.
- No Tailscale phase/module under `scripts/lib/`.
- No Tailscale verification in tests/Molecule.
- No ADR-level locked contract text yet declaring Tailscale mandatory.

## 6. Priority Gap Backlog (Recommended Order)

1. **P1**: Baseline hardening completion  
Implement explicit fail2ban enable/jail config and unattended-upgrades config/service checks.

2. **P1**: Missing host baseline controls  
Add hostname and timezone phases with config variables and verification.

3. **P1**: Edge service lifecycle completion  
Add `openclaw-edge.service` (and optional `openclaw-apps.service`) generation/management.

4. **P1**: Hub landing service lifecycle + autodiscovery  
Auto-create a `hub` service (`hub.<APPS_DOMAIN>` and optional `apps.<DOMAIN>` alias) immediately after first registered edge app, with automatic app cards from container labels and URL click-through to each real app host.

5. **P1**: Tailscale mandatory integration  
Introduce `tailscale` phase and required vars/flow. Default install path must include Tailscale setup and validation (non-interactive where possible, with explicit authkey/device-auth mode handling).

6. **P2**: Docker socket proxy hardening  
Add optional socket-proxy integration and wire Traefik to proxy endpoint when enabled.

7. **P3**: Operator QoL  
Add MOTD status script and Oh-My-Zsh optional setup.

8. **P3**: Resilience improvements from research  
Add state-file resume and optional backup/restore/diagnose modes.

## 7. Immediate Next Implementation Slice

Suggested next slice to close the highest-risk gaps:

1. `scripts/lib/system.sh` (hostname + timezone + unattended/fail2ban config management)
2. `scripts/lib/edge_systemd.sh` (edge/apps systemd units)
3. Extend `config/example.env` + `scripts/lib/config.sh` validations for new flags
4. Add/extend tests for these phases and verification assertions

## 8. New Requirement Contract: Auto Hub Service

Requirement added:

1. A hub service must be created automatically once the first edge app is created.
2. Hub host should support `hub.<DOMAIN>` and/or `apps.<DOMAIN>` routing.
3. Hub must auto-discover edge apps and render modern/minimal landing cards from live container metadata.
4. Clicking a hub app card must open the app’s actual assigned subdomain URL.

Recommended technical approach:

1. Use Homepage as the hub container (supports Docker automatic service discovery from labels).
2. Provision the hub from the app-deploy path (`deploy_app.sh`) instead of gateway hooks:
   - `deploy_app.sh` already owns app registration lifecycle and is guaranteed in the policy contract.
   - OpenClaw hooks are command/lifecycle oriented and do not provide a native "app deployed" event.
3. Extend app registration (`register_app.py`) to write Homepage discovery labels per app:
   - `homepage.group`
   - `homepage.name`
   - `homepage.icon` (deterministic pseudo-random icon assignment from curated list)
   - `homepage.href` (must be `https://<appName>.<APPS_DOMAIN>`)
   - `homepage.description`
4. Add `ensure_hub.sh`:
   - if app count transitions from 0 -> 1, generate and start hub compose service
   - route `hub.<APPS_DOMAIN>` and optional alias (`apps.<DOMAIN>`) via Traefik labels
   - configure Homepage docker integration via socket-proxy endpoint (preferred) or constrained fallback
5. Keep hub data source simple:
   - primary: Docker label autodiscovery (app name/url/icon/status)
   - optional enhancement: add a compact "raw docker ps" widget/section for operator diagnostics

Rationale:

1. Homepage has first-class automatic service discovery for Docker containers using `homepage.*` labels.
2. Homepage supports Docker integration through socket proxy, aligning with our socket-hardening gap item.
3. This design keeps app onboarding deterministic and avoids brittle post-hoc parsing of OpenClaw chat logs.

## 9. Required Contract Updates

To prevent requirement drift, these docs must be updated before implementation:

1. `docs/ARCHITECTURE_DECISION.md`:
   - add Tailscale as mandatory baseline requirement
   - add hub auto-creation + subdomain click-through contract
2. `config/example.env` + `scripts/lib/config.sh`:
   - add mandatory Tailscale config surface and validation rules
