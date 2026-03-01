# Base Script Analysis: `RareCloudio/openclaw-setup/setup.sh`

## Purpose

This document explains the upstream base script we are adopting as a starting point for a Bash-first rebuild of this repository.

Source analyzed:
- `https://github.com/RareCloudio/openclaw-setup`
- `setup.sh` (1041 lines)
- `README.md`, `SECURITY.md`, `CONTRIBUTING.md`

## What the Upstream Script Does

`setup.sh` is a single, non-interactive root installer for Ubuntu 24.04 that:

1. Validates runtime prerequisites (`root`, not already provisioned).
2. Parses flags:
- `--gateway-token`
- `--ssh-port` (default `41722`)
- `--desktop` (XFCE/VNC mode)
3. Generates a random gateway token when omitted.
4. Installs baseline packages and security tooling (`nftables`, `fail2ban`, `unattended-upgrades`, `apparmor`, etc.).
5. Installs Google Chrome (and Firefox in desktop mode).
6. Installs Node.js 22 and Docker CE.
7. Creates a local `openclaw` OS user and workspace.
8. Installs OpenClaw globally via npm (`openclaw@latest`).
9. Runs non-interactive `openclaw onboard` for local gateway mode.
10. Patches `~openclaw/.openclaw/openclaw.json` to enforce gateway on loopback with token auth.
11. Writes `/home/openclaw/.env` template.
12. Applies SSH changes (custom port, multiple hardening knobs, disables ssh socket activation).
13. Applies firewall with `nftables` and disables `ufw`.
14. Configures `fail2ban` jail for ssh on custom port.
15. Enables unattended security updates.
16. Applies sysctl hardening.
17. Writes Docker daemon hardening config.
18. Disables selected services (`avahi`, `cups`, `bluetooth`, `snapd`).
19. Writes an AppArmor profile for OpenClaw.
20. Creates and enables `openclaw-gateway.service`.
21. Installs helper scripts:
- `/usr/local/bin/openclaw-status`
- `/usr/local/bin/openclaw-backup`
- `/usr/local/bin/openclaw-security-check`
22. Creates daily backup cron job.
23. Writes a custom MOTD with post-install instructions.
24. Persists install marker and credentials to `/opt/openclaw-setup`.

## Execution Model and Idempotence Notes

- Script uses `set -euo pipefail` and logs to `/var/log/openclaw-setup.log`.
- It is intended as one-shot provisioning.
- Re-run behavior is blocked by `/opt/openclaw-setup/.provisioned` unless manually removed.
- Several operations are append-oriented (`echo >>`) and are not strictly idempotent.
- Some steps use `|| true`, which prevents hard failure but may hide partial configuration issues.

## Security Model Implemented Upstream

Upstream documents an 8-layer model:
1. nftables inbound lock-down
2. fail2ban
3. SSH hardening
4. gateway token auth
5. AppArmor confinement
6. Docker sandbox isolation
7. systemd hardening intent
8. desktop screen lock in desktop mode

Important actual behavior in script:
- Gateway binds to `127.0.0.1:18789`.
- Firewall defaults to nftables-only and disables ufw.
- SSH default port is `41722`.
- `PermitRootLogin yes` is explicitly set.
- `DenyUsers openclaw` is set to prevent SSH login for the service user.

## Gaps Against Our Target Preferences

These are the major mismatches we must override in our project:

1. SSH posture mismatch:
- Upstream: `PermitRootLogin yes`, custom port default `41722`.
- Our target: disable root SSH login, disable password auth, use port `1773`, key-only auth.

2. User model mismatch:
- Upstream: fixed service account `openclaw`; no custom admin bootstrap as primary access user.
- Our target: admin user from env config, sudo-enabled, authorized key managed; no `ubuntu` user retained.

3. Firewall strategy mismatch:
- Upstream: nftables only, disables ufw.
- Our target: support our firewall policy model (including tufw/ufw preference) and avoid policy conflicts with OpenClaw and Traefik requirements.

4. Infra integration gap:
- Upstream has no Cloudflare DNS/SSL automation, no Traefik stack automation, no docker-socket-proxy pattern for reverse proxy safety.

5. Shell ergonomics gap:
- Upstream does not provision Oh-My-Zsh `guru2` + `git` plugin for admin user.

6. Host identity gap:
- Upstream does not provide configurable hostname/FQDN and host IP mapping workflow.

7. Testing gap:
- Upstream itself calls out missing automated tests.
- Our project requires local reproducible tests (Molecule + Vagrant).

## Keep / Modify / Remove Matrix for Bash Rebuild

Keep:
- Single-command bootstrap style.
- Loopback-only OpenClaw gateway and token-based access.
- fail2ban + unattended-upgrades + baseline package provisioning.
- systemd service for OpenClaw gateway.
- helper diagnostics concept (`openclaw-status`, security checks).
- post-install operator guidance in MOTD/readme.

Modify:
- SSH defaults: port `1773`, `PermitRootLogin no`, `PasswordAuthentication no`, key-only.
- User bootstrap: configurable admin user from env; grant sudo; configure authorized key.
- Firewall behavior to fit our desired model and reverse-proxy needs.
- MOTD content to include docker/openclaw/fail2ban/resource/public IP status blocks.
- introduce Docker socket proxy support.
- introduce Cloudflare + Traefik integration path.
- add hostname/FQDN configuration from env.

Remove or avoid by default:
- Hard-coded root-centric operational flow in final guidance.
- Forced desktop mode assumptions unless explicitly enabled.
- non-deterministic append patterns that hurt idempotence.

## Suggested Config Surface for Our Script

Expected `.env`/config variables for our Bash implementation:

Core host and access:
- `INFRA_HOSTNAME`
- `INFRA_FQDN`
- `INFRA_SERVER_IP` (optional, for hosts file and checks)
- `INFRA_ADMIN_USER`
- `INFRA_ADMIN_SSH_PUBLIC_KEY`
- `INFRA_ADMIN_PASSWORD_HASH` (optional; avoid plaintext password)
- `SSH_PORT` (default `1773`)

OpenClaw and gateway:
- `OPENCLAW_ENABLE`
- `OPENCLAW_INSTALL_MODE`
- `OPENCLAW_GATEWAY_TOKEN`

Cloudflare/edge:
- `CLOUDFLARE_ZONE_ID`
- `CLOUDFLARE_GLOBAL_API_KEY` (legacy fallback)
- `CLOUDFLARE_DNS_API_TOKEN` (preferred)
- `CLOUDFLARE_ACCOUNT_EMAIL` (when required by API path)

Traefik/TLS (if enabled):
- `TRAEFIK_ENABLE`
- `TRAEFIK_DOMAIN`
- `TRAEFIK_HUB_HOST`
- `TRAEFIK_CF_ORIGIN_CERT`
- `TRAEFIK_CF_ORIGIN_KEY`

## Testing Direction (Bash-first)

We should keep Molecule + Vagrant and rewire scenarios to run shell-based converge:

- Docker scenario: quick checks for base package + config rendering behavior.
- Vagrant scenario: full host-style test for SSH hardening, firewall, fail2ban, unattended-upgrades, hostname, user bootstrap.
- Optional integration scenario: Traefik + Cloudflare variable rendering and service health checks (without external DNS mutation in CI).

## Recommended Next Refactor Step

1. Replace the current Ansible-first control plane with a `scripts/install.sh` orchestrator.
2. Split logic into reusable bash modules (packages, users, ssh, firewall, openclaw, cloudflare, traefik, motd, verify).
3. Add `make test-*` wrappers around Molecule scenarios that execute the shell installer.
4. Keep all security defaults opinionated and non-interactive, with explicit override vars.

This keeps the upstream strengths while aligning with our stricter SSH/user policy and our reverse-proxy/Cloudflare architecture.
