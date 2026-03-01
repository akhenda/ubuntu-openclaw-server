# Research Note: `MundoFacu/openclaw-vm-setup`

Reference:
- Repo: `https://github.com/MundoFacu/openclaw-vm-setup`
- Script: `setup_openclaw.sh`
- Context: `README.md`, `LICENSE`

## Snapshot of Approach

A focused Bash script for Ubuntu VM isolation that installs OpenClaw under a dedicated non-admin user and applies outbound network containment to prevent lateral movement on local LAN.

Main flow:
1. Confirm root execution and ask for interactive confirmation.
2. Update system and install build dependencies.
3. Create 2GB swap file if missing.
4. Install Node.js 24.
5. Create `openclaw` user with temporary NOPASSWD sudo.
6. Install OpenClaw globally via npm.
7. Enable systemd lingering for user services.
8. Revoke `openclaw` sudo privileges.
9. Apply iptables/ip6tables OUTPUT rules to allow only gateway/internet and block local subnet lateral traffic.
10. Print manual next steps for onboarding, daemon, security audit, pairing.

## What It Does Well

1. Strong least-privilege intent for service account.
- Explicitly revokes sudo from `openclaw` after installation.

2. Good VM threat-model awareness.
- Emphasizes isolation and snapshot strategy.
- Addresses lateral movement risk on flat LANs with explicit egress filtering.

3. Practical reliability detail.
- Adds swap proactively for low-memory VPS/VM installations.

4. Keeps gateway exposure guidance conservative.
- Recommends loopback bind and no direct port exposure.

## Risks / Tradeoffs

1. No SSH/server-access hardening path.
- Does not configure SSH port, root login policy, password policy, fail2ban, or unattended-upgrades.
- Leaves core host-access baseline to operator/manual controls.

2. Interactive execution.
- Requires terminal confirmation and manual post-install onboarding steps.
- Not fully suitable as deterministic infrastructure automation baseline.

3. Firewall scope is narrow and specialized.
- Uses iptables OUTPUT-only LAN isolation, but not full host ingress hardening framework.
- Can conflict with environments needing LAN access to specific services unless manually adapted.

4. OpenClaw provisioning is partial.
- Installs binary but expects manual onboarding/daemon setup/security audit execution.

5. Fixed user and runtime assumptions.
- Hard-codes `openclaw` user and Node major version.

## Keep / Modify / Reject for Our Toolkit

Keep:
1. Service-user least-privilege model (temporary elevation then revoke).
2. Swap bootstrap option for constrained hosts.
3. VM/lateral-movement defense concept (egress control profiles).
4. Conservative loopback-first gateway exposure guidance.

Modify:
1. Add full access/security baseline around it:
- SSH on `1773`
- `PermitRootLogin no`
- `PasswordAuthentication no`
- admin user/key bootstrap from env
- fail2ban + unattended-upgrades + hostname policy

2. Execution model:
- remove interactive confirms from primary automation path
- keep optional prompts only for manual mode

3. Network policy:
- make LAN egress lockdown a selectable profile, not universal default
- integrate with Traefik/Cloudflare/OpenClaw modes so rules do not conflict

4. OpenClaw setup:
- automate full non-interactive onboarding/config path where supported
- include deterministic service creation and health verification

Reject (as defaults):
1. SSH/security omission in base installer.
2. Hard-coded user-only model without env-driven admin controls.
3. Fully manual post-install sequence as primary operational flow.

## Useful Ideas to Port

1. Add an optional `network_profile=isolated_vm` mode implementing gateway-only LAN egress.
2. Add `swap_enable` and `swap_size` config flags with safe defaults.
3. Preserve the explicit "temporary privilege then revoke" install pattern.
4. Keep post-install checklist quality, but couple it with automated verification outputs.

## Mapping to `plans/APPROVED_BASE_PLAN.md`

Supports:
1. Step 3 (baseline services/security): contributes swap + egress-isolation concepts.
2. Step 4 (OpenClaw core): supports dedicated service user pattern.
3. Step 6 (operator UX): strong operational guidance language worth adapting.

Divergences we keep intentionally:
1. We must add complete SSH/access hardening as first-class baseline.
2. We keep env-driven admin model instead of fixed `openclaw` access workflow.
3. We keep non-interactive default automation and testable convergence behavior.
