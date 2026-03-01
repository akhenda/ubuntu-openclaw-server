# Research Note: `stfurkan/claw-easy-setup`

Reference:
- Repo: `https://github.com/stfurkan/claw-easy-setup`
- Script: `setup-server.sh`
- Context: `README.md`

## Snapshot of Approach

A single Bash script for Debian/Ubuntu that creates an admin user, hardens SSH, enables UFW/fail2ban/unattended-upgrades, installs OpenClaw via upstream installer, configures user daemon startup, then reboots automatically.

Default posture in script:
1. User defaults to `openclaw`.
2. SSH port defaults to `2222`.
3. Root SSH disabled.
4. Password authentication intentionally kept enabled initially (`PasswordAuthentication yes`) for safety.
5. UFW allows only SSH port; OpenClaw UI remains local and is accessed via SSH tunnel.

## What It Does Well

1. Good lockout-safety sequencing.
- Applies SSH config before enabling firewall.
- Validates SSH config with `sshd -t` before restart.

2. Uses SSH drop-in config (`/etc/ssh/sshd_config.d/00-openclaw-security.conf`).
- More reliable than editing only `/etc/ssh/sshd_config`, especially with cloud-init drop-ins.

3. Practical baseline hardening.
- UFW default deny incoming.
- fail2ban configured for chosen SSH port.
- unattended-upgrades enabled.

4. Useful production details.
- Adds swap file when absent.
- Handles user-level daemon persistence via systemd linger.

## Risks / Tradeoffs

1. Interactive path is mandatory.
- Prompts for user password.
- Runs interactive OpenClaw installer flow.
- This conflicts with our requirement for deterministic non-interactive automation.

2. SSH password auth remains enabled by default.
- Provides optional manual command to disable later.
- Our standard is key-only SSH immediately.

3. User/key bootstrap model is weak for automation.
- No env-based required public key input.
- If root key exists, it copies root authorized_keys to new user.

4. Forced reboot at script end.
- Can interrupt orchestration pipelines and automated validation.

5. Temporary NOPASSWD sudo grant.
- Short-lived, but still a privilege expansion path.

6. OpenClaw install method divergence.
- Uses `openclaw.ai/install.sh` and user daemon flow, not `openclaw/openclaw-ansible` local pattern we previously standardized.

## Keep / Modify / Reject for Our Toolkit

Keep:
1. SSH drop-in config strategy under `sshd_config.d`.
2. Pre-firewall SSH migration order + `sshd -t` guard.
3. Baseline controls: UFW + fail2ban + unattended-upgrades.
4. Optional swap provisioning idea for low-memory servers.

Modify:
1. SSH posture:
- default to port `1773`
- set `PermitRootLogin no`
- set `PasswordAuthentication no` by default
- require explicit admin public key from env/config

2. User model:
- env-driven admin username
- key-based auth first
- optional password policy, not mandatory interactive prompt

3. Execution model:
- remove mandatory interactive prompts
- remove forced reboot (make it opt-in via config)

4. OpenClaw integration:
- align with our final selected installation strategy and service model

Reject (as defaults):
1. Password-first onboarding as baseline.
2. Copying root SSH keys as primary bootstrap mechanism.
3. Automatic reboot without operator/config toggle.

## Useful Ideas to Port

1. Use a managed `sshd_config.d/00-*.conf` drop-in file.
2. Preserve explicit post-run SSH tunnel guidance for local-only gateway access.
3. Keep SSH syntax validation + auto-rollback safety patterns.

## Mapping to `plans/APPROVED_BASE_PLAN.md`

Supports:
1. Step 2 (access lockdown): validates safe SSH migration sequencing.
2. Step 3 (baseline services): confirms practical baseline package set and fail2ban/UFW ordering.
3. Step 4 (OpenClaw core): demonstrates user-service boot persistence patterns worth adapting.

Divergences we will keep intentionally:
1. Our SSH default stays `1773` (not `2222`).
2. Our baseline is immediate key-only SSH, no deferred manual hardening.
3. Our run path remains non-interactive by default.
