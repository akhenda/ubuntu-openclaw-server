# Research Note: `locryns/vm-linux-hardening-setup`

Reference:
- Repo: `https://github.com/locryns/vm-linux-hardening-setup`
- Script: `setup.sh`
- Context: `README.md`

## Snapshot of Approach

A monolithic root-run Bash script (Ubuntu 22.04+ / Debian 12+) that hardens a VM around a Tailscale-first access model, installs OpenClaw tooling, and configures fallback SSH backdoor access.

Core flow implemented:
1. Install baseline packages (`ufw`, `fail2ban`, `unattended-upgrades`, `auditd`, etc.).
2. Create admin user from CLI arg + `<username>.pub` file.
3. Harden SSH (`PasswordAuthentication no`, `PermitRootLogin no`).
4. Install/connect Tailscale (`tailscale up --ssh`, interactive).
5. Apply strict UFW policy allowing only `tailscale0` traffic plus a public rate-limited backdoor port.
6. Bind main SSH daemon to Tailscale IP only (`ListenAddress <tailscale_ip>`).
7. Install OpenClaw (+ OpenCode + Claude Code).
8. Configure OpenClaw gateway on Tailscale IP with generated token.
9. Configure separate "backdoor" sshd service on a hidden public port.
10. Tune fail2ban for both main sshd and backdoor endpoint.

## What It Does Well

1. Strong key-only access defaults and root SSH denial.
2. Good preflight validation (username format, pubkey existence, pubkey parse check).
3. Clear defensive sequencing with `sshd -t` validation before restart.
4. Uses idempotent checks in many steps (`already exists` patterns).
5. Provides DRY_RUN mode and clear human-readable logging.
6. Applies systemd hardening controls for OpenClaw gateway service (`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem`).

## Risks / Tradeoffs

1. Interactive dependency in provisioning path.
- `tailscale up --ssh` introduces operator interaction and may block fully non-interactive automation.

2. Emergency backdoor increases attack surface.
- Secondary public `sshd` listener (even rate-limited/key-only) is still a persistent external entrypoint.

3. SSH model differs from our standard.
- Keeps SSH on port `22` but bound to `tailscale0`; our baseline requires explicit SSH port `1773` policy.

4. OpenClaw install source differs from our intended strategy.
- Uses `openclaw.ai/install.sh` / npm fallback rather than `openclaw/openclaw-ansible` local-run pattern.

5. UFW reset behavior can clobber prior policy.
- `ufw --force reset` simplifies convergence but may remove expected pre-existing rules.

6. Sudo policy is highly permissive.
- Creates NOPASSWD sudo for target user by default.

## Keep / Modify / Reject for Our Toolkit

Keep:
1. Preflight validation quality (arg + key checks).
2. SSH config safety pattern (`sshd -t` before restart; rollback on failure).
3. DRY_RUN and structured logging ergonomics.
4. Service-level hardening for long-running daemons.

Modify:
1. Access baseline:
- use SSH port `1773`
- keep `PermitRootLogin no`
- keep `PasswordAuthentication no`
- support non-interactive, env-driven admin user + key config (not `<username>.pub` file coupling)

2. Network posture:
- avoid permanent public backdoor by default (make emergency mode optional, explicit, off by default)
- align firewall with our final Traefik/OpenClaw architecture and explicit policy toggles

3. OpenClaw provisioning:
- integrate our chosen installer path and deterministic config rendering

4. Automation behavior:
- remove interactive prompts from primary run path (Tailscale auth and confirmations should be opt-in or pre-seeded vars)

Reject (as defaults):
1. Mandatory Tailscale-only SSH binding in baseline install.
2. Always-on public backdoor sshd service.
3. NOPASSWD sudo as unconditional default.

## Useful Ideas to Port

1. `DRY_RUN=1` execution mode (good for safe previews).
2. Strong preflight checks for required secrets/keys before any destructive step.
3. Split main SSH and emergency access configs (if we add a break-glass mode later).
4. Explicit summary section with operational next steps and status pointers.

## Mapping to `plans/APPROVED_BASE_PLAN.md`

Supports and improves:
1. Step 1 (framework): reinforces modular function design and logging discipline.
2. Step 2 (access lockdown): validates our direction on key-only + root deny; adds robust validation patterns.
3. Step 3 (baseline security): offers practical UFW/fail2ban sequence ideas.
4. Step 4 (OpenClaw core): provides service hardening examples for gateway unit files.

Divergences we intentionally keep:
1. We keep SSH port `1773` baseline instead of Tailscale-only port 22.
2. We avoid default always-on public backdoor.
3. We keep full non-interactive automation for primary install path.
