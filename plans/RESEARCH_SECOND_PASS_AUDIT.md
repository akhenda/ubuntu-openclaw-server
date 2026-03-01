# Research Second-Pass Audit (Post-Implementation Reconciliation)

Date: 2026-03-01
Purpose: Reconcile each research source against the current Bash toolkit and verify that no source-driven requirement was silently dropped.

## 1. `rarecloud-openclaw-setup`

Adopted:
1. Operational MOTD concept (implemented via `scripts/lib/motd.sh`)
2. Explicit fail2ban + unattended management intent (implemented via `scripts/lib/system.sh`)

Not adopted (deferred):
1. AppArmor profile automation
2. Extended helper command bundle (`status`, backups, etc.)

## 2. `locryns-vm-linux-hardening-setup`

Adopted:
1. Tailscale as admin-plane baseline (implemented in `scripts/lib/tailscale.sh`)
2. Hardened SSH sequencing/validation discipline

Not adopted (intentional):
1. Public/backdoor SSH split profile
2. Overly permissive emergency defaults

## 3. `stfurkan-claw-easy-setup`

Adopted:
1. `sshd_config.d` drop-in pattern
2. Lockout-safe sequencing around SSH and firewall phases

Deferred:
1. Swap bootstrap

## 4. `mundofacu-openclaw-vm-setup`

Adopted:
1. Least-privilege runtime/user separation model

Deferred:
1. Optional isolated-egress profile
2. Swap provisioning convenience path

## 5. `eyal050-openclaw-remote-install`

Adopted:
1. Phased execution architecture and explicit helper interfaces
2. High observability intent (structured logs + verify phase)

Deferred:
1. Backup/restore mode
2. Dedicated diagnose mode
3. Remote wrapper orchestration mode

## 6. `phucmpham-deploy-openclaw`

Adopted:
1. Safety-first sequencing and shell test discipline
2. Tailscale requirement alignment

Deferred:
1. Full stateful resume/rollback framework across all phases
2. BATS-specific harness migration

## 7. `mortalezz-openclaw`

Adopted:
1. Local runtime and systemd lifecycle operational model

Deferred:
1. Reboot-resume automation
2. Minimal-image dbus/user-systemd profile handling

## 8. `custom-cloudflare-tunnel-traefik-openclaw`

Adopted (primary blueprint, implemented):
1. Cloudflare Tunnel -> Traefik -> apps topology
2. Global apps compose ownership + helper-driven app registration
3. Hub auto-discovery model with app-card click-through URLs
4. DNS wildcard-first + per-host fallback helpers
5. Policy injection and reporting helper contract
6. Edge/gateway/apps systemd lifecycle model

## 9. Consolidated Findings

Closed in this implementation phase:
1. Mandatory Tailscale integration
2. Hub auto-create and app-card click-through
3. Socket proxy hardening
4. Hostname/timezone + fail2ban/unattended baseline completion
5. Edge/apps systemd lifecycle completion
6. MOTD + Oh-My-Zsh operator UX

Remaining deferred items:
1. Swap and memory-profile automation
2. Reboot-resume/state-machine capabilities
3. Backup/restore and diagnose utilities
4. Optional isolated-egress profile
5. Deeper systemd sandbox hardening profile

## 10. Conclusion

No research item was omitted. Required items from the approved implementation phase are now represented in code and tests. Remaining items are explicitly deferred and tracked as future enhancements, not unacknowledged gaps.
