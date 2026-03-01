# Implementation Gap Matrix (Post-Implementation Audit)

Date: 2026-03-01
Audit scope:
- `docs/ARCHITECTURE_DECISION.md`
- `plans/APPROVED_BASE_PLAN.md`
- `plans/RESEARCH_SECOND_PASS_AUDIT.md`
- Implementation under `scripts/`, `config/`, `tests/`, `molecule/`, `Makefile`, `README.md`

## 1. Executive Summary

Status: **Core implementation contract is complete for this phase**.

All previously identified P1/P2 gaps from the first matrix are now implemented and validated in local test workflows:
1. Mandatory Tailscale phase
2. Hostname/timezone + fail2ban/unattended baseline phase
3. Hub auto-create on first app deploy with app-card click-through links
4. Socket proxy integration for Traefik and hub discovery
5. Edge/OpenClaw/apps systemd lifecycle units
6. MOTD and Oh-My-Zsh operator UX

Validation status from current branch:
1. `make lint` passed
2. `make test-scripts` passed
3. `make test-docker` passed
4. `make test-vagrant` passed

## 2. Approved Base Plan Coverage

| Approved Plan Item | Status | Evidence | Remaining Gap |
|---|---|---|---|
| Bash modular framework + env contract | Implemented | `scripts/install.sh`, `scripts/lib/*.sh`, `config/example.env` | None |
| Access lockdown (SSH 1773, root off, password off, key-only admin) | Implemented | `scripts/lib/ssh.sh`, `scripts/lib/user.sh`, `scripts/lib/config.sh` | None |
| Baseline system security/services | Implemented | `scripts/lib/system.sh`, `scripts/lib/firewall.sh`, `scripts/lib/verify.sh` | None |
| OpenClaw core + policy injection + runtime files | Implemented | `scripts/lib/openclaw.sh` | None |
| Reverse-proxy integration (Cloudflare + Traefik + socket proxy) | Implemented | `scripts/lib/edge.sh`, `scripts/lib/dns.sh`, `scripts/lib/socket_proxy.sh` | None |
| Operator QoL (MOTD + Oh-My-Zsh) | Implemented | `scripts/lib/motd.sh`, `scripts/lib/oh_my_zsh.sh` | None |
| Shell-first tests (scripts + molecule docker/vagrant) | Implemented | `tests/*.sh`, `molecule/docker/*`, `molecule/vagrant/*` | None |
| Control surface/docs update | Implemented | `Makefile`, `README.md`, docs set | None |

## 3. Architecture Decision Contract Coverage

| Architecture Contract | Status | Evidence | Remaining Gap |
|---|---|---|---|
| Cloudflare Tunnel -> Traefik -> app containers | Implemented | `scripts/lib/edge.sh`, `scripts/lib/apps.sh` | None |
| No public app port publishing in app flow | Implemented | Generated app services use Traefik labels only (`register_app.py`) | None |
| `openclaw-edge` network + static IP reservations | Implemented | `scripts/lib/config.sh`, `scripts/lib/edge.sh` | None |
| Dual-user model (`hendaz` admin, `openclaw` runtime) | Implemented | `scripts/lib/user.sh`, config validations | None |
| Mandatory workspace policy injection | Implemented | `openclaw.json` hook config + AGENTS policy rendering in `scripts/lib/openclaw.sh` | None |
| DNS wildcard preferred + per-host fallback | Implemented | Generated `cf_dns_ensure_wildcard.sh` + `cf_dns_upsert_subdomain.sh` | None |
| Hub autoprovision + click-through URLs | Implemented | Generated `ensure_hub.sh`; `homepage.href=https://<app>.<APPS_DOMAIN>` labels | None |
| Socket-proxy isolation for Docker API exposure | Implemented | `docker-socket-proxy` service + Traefik endpoint wiring | None |
| Stack systemd lifecycle units | Implemented | `scripts/lib/systemd.sh` manages edge/gateway/apps units | None |

## 4. Research Source Coverage (One-by-One)

| Research Source | Status in current implementation | Deferred |
|---|---|---|
| `rarecloud-openclaw-setup` | Adopted key baseline ideas (MOTD pattern, fail2ban/unattended management) | AppArmor profile mode not yet implemented |
| `locryns-vm-linux-hardening-setup` | Adopted Tailscale-first admin plane + SSH hardening discipline | Break-glass/public backdoor profile intentionally not implemented |
| `stfurkan-claw-easy-setup` | Adopted sshd drop-in + validation sequencing patterns | Swap bootstrap not implemented |
| `mundofacu-openclaw-vm-setup` | Adopted least-privilege runtime model | Optional isolated-egress profile not implemented |
| `eyal050-openclaw-remote-install` | Adopted phased execution style + explicit helper contract model | Backup/restore + diagnose wrapper not implemented |
| `phucmpham-deploy-openclaw` | Adopted shell testing discipline + safety-first sequencing | Full state-resume framework beyond current scope |
| `mortalezz-openclaw` | Adopted local-runtime/systemd operational mindset | Reboot-resume and minimal-image dbus profile checks not implemented |
| `custom-cloudflare-tunnel-traefik-openclaw` | Implemented as primary architecture (edge stack, DNS helpers, policy injection, apps registry, reporting helper) | None in current phase scope |

## 5. Residual Gaps (Deferred by Scope)

These are not regressions; they remain future enhancements outside the completed phase:
1. Swap-management feature toggle
2. Reboot-resume/state-machine workflow
3. Backup/restore and diagnose operational modes
4. Optional isolated-egress profile
5. Additional service hardening directives (systemd sandbox depth)
6. Potential BATS migration (current tests are shell + Molecule)

## 6. Contract Drift Corrections Applied During Audit

To keep canonical docs aligned with implementation, this audit pass updated:
1. `docs/ARCHITECTURE_DECISION.md`
- edge stack definition now includes `docker-socket-proxy` (when enabled)
- reserved app names now include `hub`
2. `scripts/lib/openclaw.sh`
- policy-injection AGENTS template now includes `hub` as reserved name
- edge stack description now references socket proxy presence

## 7. Final Audit Verdict

Verdict: **Phase complete and internally consistent**.

The repository now satisfies the approved implementation plan for mandatory Tailscale, hub autoprovisioning, socket proxy hardening, baseline system hardening completion, lifecycle systemd management, and local testability via Molecule docker/vagrant.
