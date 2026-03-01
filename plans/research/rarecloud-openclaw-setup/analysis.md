# Research Note: RareCloud `openclaw-setup` Approach

Reference:
- Repo: `https://github.com/RareCloudio/openclaw-setup`
- Script: `setup.sh`
- Context docs: `README.md`, `SECURITY.md`, `CONTRIBUTING.md`

## Snapshot of Approach

A monolithic root-run Bash script provisions Ubuntu 24.04 in one pass, installs OpenClaw directly on host, applies hardening controls, and prints operator next steps.

Key characteristics:
1. One-shot flow with a provisioned flag.
2. Opinionated defaults (`SSH_PORT=41722`, desktop mode optional).
3. Gateway loopback binding with token auth.
4. nftables + fail2ban + unattended upgrades + AppArmor.
5. Helper scripts and MOTD for operations.

## Strengths to Keep

1. Loopback-only gateway (`127.0.0.1:18789`) and token auth.
2. Fast bootstrap with practical dependency install order.
3. Built-in post-install operability (status/check/backup helpers).
4. Baseline security stack (fail2ban, unattended-upgrades, hardening intent).
5. Clear UX messaging through logs and MOTD.

## Weaknesses / Risks

1. Access policy conflict with our standard:
- Enables root SSH login (`PermitRootLogin yes`).
- Default custom SSH port is `41722`, not our `1773`.
- Root-centric reconnect guidance.

2. Firewall opinion may conflict with our stack:
- Disables `ufw` and forces nftables model.
- Could conflict with evolving Traefik/OpenClaw ingress policy.

3. Idempotence limitations:
- One-shot provision flag stops safe iterative convergence.
- Some append-style config writes can drift over reruns.

4. Flexibility gap:
- Fixed service user model and limited env-driven admin bootstrap.
- No native Cloudflare/Traefik/socket-proxy setup path.

5. Testing gap:
- Upstream acknowledges limited automated test coverage.

## Keep / Modify / Reject for Our Toolkit

Keep:
1. Local-only gateway and token-based auth model.
2. Service/bootstrap concept for OpenClaw.
3. Operational helpers + explicit post-install guidance.

Modify:
1. SSH hardening:
- enforce `Port 1773`
- enforce `PermitRootLogin no`
- enforce `PasswordAuthentication no`
- key-only admin access

2. User model:
- custom sudo admin user from env
- authorized keys from env/config
- remove/disable default cloud image user as policy requires

3. Firewall behavior:
- align with our chosen policy framework and reverse-proxy requirements

4. Extensibility:
- modular script architecture (`scripts/lib/*.sh`) instead of monolith

Reject (as default behavior):
1. Root-login-enabled SSH posture.
2. Hardwired root-first operations messaging.
3. Non-restartable one-shot convergence as the primary model.

## Actionable Ideas to Port Immediately

1. Preserve helper command ergonomics (`status`, `security-check`, backups).
2. Preserve strict input validation for tokens/ports.
3. Preserve clear final summary output and credentials location.
4. Preserve loopback bind and tokenized UI access patterns.

## Mapping to Our Approved Base Plan

This research directly supports:
1. Step 2 (SSH and access lockdown) by identifying exact mismatch points.
2. Step 4 (OpenClaw core install) by preserving proven gateway bootstrap concepts.
3. Step 6 (operator UX) by reusing helper and MOTD strategy in an improved form.

## Follow-up Questions for Future Research Notes

When reviewing each new external script/doc, we will classify:
1. Does it improve security posture over our current baseline?
2. Does it improve idempotence and rerun safety?
3. Does it improve testability in docker/vagrant scenarios?
4. Is it compatible with our Cloudflare + Traefik + OpenClaw architecture?
