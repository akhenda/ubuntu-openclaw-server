# Approved Base Plan: Bash-First Ubuntu 24.04 OpenClaw Toolkit

Status: Approved by user.

## Objective

Build a modular, testable, Bash-first automation toolkit for Ubuntu Server 24.04 that provisions a secure OpenClaw host with optional Cloudflare, Traefik, socket proxy, MOTD observability, and operator ergonomics.

## Guiding Rules

1. Security-first defaults.
2. Idempotent and re-runnable behavior where feasible.
3. Small, modular shell components over one huge script.
4. Test every phase with Molecule (docker fast path, vagrant full path).
5. Commit in small increments with verification at each step.

## Approved Execution Sequence

1. Create Bash framework first.
- `scripts/install.sh`
- `scripts/lib/*.sh` modules:
  - `common.sh`
  - `packages.sh`
  - `user.sh`
  - `ssh.sh`
  - `firewall.sh`
  - `openclaw.sh`
  - `cloudflare.sh`
  - `traefik.sh`
  - `motd.sh`
  - `verify.sh`
- `config/example.env`

2. Lock down access before anything else.
- Admin user from env.
- Authorized key installation.
- `PermitRootLogin no`.
- `PasswordAuthentication no`.
- SSH port `1773`.
- Safe pre/post checks before ssh service restart.

3. Add baseline system security/services.
- `fail2ban`
- `unattended-upgrades`
- timezone
- hostname/FQDN
- firewall policy aligned with our target architecture (and future Traefik/OpenClaw behavior)

4. Add OpenClaw core install path.
- install Node/Docker/OpenClaw
- configure loopback gateway + token auth
- systemd service
- health checks

5. Add reverse-proxy stack integration.
- Docker socket proxy
- Traefik foundation
- Cloudflare integration hooks/config surface

6. Add operator quality-of-life.
- MOTD with status blocks
- Oh-My-Zsh (`guru2`, `git`) for admin user

7. Rewire tests to shell-based convergence.
- Molecule docker scenario: fast baseline checks.
- Molecule vagrant scenario: full host validation.

8. Update control surface and docs.
- Make targets for lint/test/run.
- runbook for real VPS usage.
- configuration guide and secrets handling.

## Baseline Security Decisions

1. SSH listens on `1773` (not `22`).
2. Root SSH login disabled.
3. Password auth disabled for SSH (key-only).
4. Admin user is custom/env-driven and sudo-enabled.
5. Gateway binds to loopback and uses token auth.

## Change Control Method

For each milestone:
1. Implement scope.
2. Run relevant tests.
3. Record outcome.
4. Commit with focused message.

## Research Workflow

External scripts/docs are analyzed into `plans/research/*.md`.
Each research note captures:
1. What it does well.
2. Risks/tradeoffs.
3. Keep/modify/reject mapping for our toolkit.
4. Actionable ideas to port.
