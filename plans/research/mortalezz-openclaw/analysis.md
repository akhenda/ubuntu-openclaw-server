# Research Note: `mortalezz/openclaw`

Reference:
- Repo: `https://github.com/mortalezz/openclaw`
- Script: `openclaw-setup.sh`
- Context: short `README.md`, `LICENSE`

## Snapshot of Approach

A Hetzner-focused Bash bootstrap for Ubuntu minimal images that installs OpenClaw with OpenRouter/Kimi defaults, handles reboot-resume, and works around user-systemd/dbus pitfalls.

Core flow:
1. Require `OPENROUTER_API_KEY`.
2. Run apt upgrade and auto-reboot/resume if kernel update requires reboot.
3. Install dependencies including `dbus-user-session`.
4. Create `openclaw` user, grant NOPASSWD sudo, enable linger.
5. Prompt to set password for `openclaw` if needed; copy root authorized_keys if present.
6. Configure UFW with allow SSH (`22`) and deny gateway port externally.
7. Install OpenClaw via `openclaw.ai/install.sh --no-onboard` as `openclaw` user.
8. Write `~openclaw/.openclaw/openclaw.json` (gateway loopback + OpenRouter model defaults).
9. Run onboarding non-interactively with warnings tolerated.
10. Drop `finish-setup.sh` for first direct SSH login as `openclaw` to complete user-systemd gateway setup.

## What It Does Well

1. Handles a real platform-specific reliability issue.
- Explicitly installs `dbus-user-session` and explains why user systemd fails on minimal images.

2. Reboot-resume mechanism is practical.
- Uses reboot detection and a temporary cron resume path to survive kernel update reboot.

3. Keeps gateway local-only.
- Config sets `gateway.bind = loopback` and blocks gateway port at firewall.

4. Configuration intent is clear.
- Model defaults, token provider, and onboarding purpose are documented in-script.

## Risks / Tradeoffs

1. Access hardening is incomplete for our baseline.
- SSH remains on port `22`.
- No explicit `PermitRootLogin no` or `PasswordAuthentication no` hardening.
- No fail2ban/unattended-upgrades baseline setup.

2. Privilege model is weak by default.
- Grants permanent `NOPASSWD:ALL` sudo to `openclaw` user and does not revoke.

3. Key/user bootstrap approach is not deterministic.
- Copies root authorized_keys if present; prompts for user password interactively.

4. Secrets handling concern.
- Writes OpenRouter API key directly into `openclaw.json` env section.

5. Partial two-phase completion.
- Requires manual direct SSH login as `openclaw` and running `finish-setup.sh` to complete service setup.

## Keep / Modify / Reject for Our Toolkit

Keep:
1. Hetzner/minimal-image dbus-user-session handling insight.
2. Reboot-resume idea for kernel-update-safe automation.
3. Loopback-first gateway bind posture.
4. User-systemd diagnostics and first-login completion checks (as optional helper).

Modify:
1. SSH/security baseline:
- enforce `1773`
- enforce `PermitRootLogin no`
- enforce `PasswordAuthentication no`
- add fail2ban + unattended-upgrades

2. User model:
- env-driven admin user creation and key injection
- avoid permanent NOPASSWD sudo for service user

3. Secrets strategy:
- avoid embedding provider keys directly in static config when possible
- move sensitive values to managed env/secret file flow

4. Execution model:
- reduce manual two-phase dependency by ensuring non-interactive completion path

Reject (as defaults):
1. Permanent NOPASSWD sudo for `openclaw`.
2. Leaving SSH on port `22` with no strict SSH hardening.
3. Interactive password prompt as required baseline behavior.

## Useful Ideas to Port

1. Add optional reboot-resume support in our installer framework.
2. Add host-profile conditionals (e.g., Hetzner/minimal image quirks).
3. Add a robust user-systemd readiness check before service setup.

## Mapping to `plans/APPROVED_BASE_PLAN.md`

Supports:
1. Step 1 (framework): profile-specific logic and resilient resume pattern.
2. Step 4 (OpenClaw core): user-systemd readiness and local gateway behavior.
3. Step 8 (docs/runbook): clear operator guidance around known host-specific pitfalls.

Divergences we keep intentionally:
1. Our secure SSH/user baseline remains stricter (`1773`, key-only, no root SSH).
2. We avoid persistent broad sudo grants to service users.
3. We keep deterministic non-interactive installation as default behavior.
