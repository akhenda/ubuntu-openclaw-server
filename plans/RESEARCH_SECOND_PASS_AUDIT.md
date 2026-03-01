# Research Second-Pass Audit (One-by-One)

Date: 2026-03-01  
Goal: Verify no research item was missed and reconcile required features against current implementation.

## 1. `rarecloud-openclaw-setup`

Confirmed important patterns:

1. MOTD operational summary and helper commands (`status`, `security-check`, backups).
2. Explicit fail2ban and unattended-upgrades hardening config.
3. AppArmor profile and nftables-first firewall posture.
4. Non-interactive onboard/service setup flow in one script.

Current gap impact:

1. MOTD is still missing in our Bash toolkit.
2. fail2ban/unattended are installed but not fully managed/configured.
3. Optional AppArmor profile support not implemented.
4. Helper command suite not implemented.

## 2. `locryns-vm-linux-hardening-setup`

Confirmed important patterns:

1. Tailscale-first secure admin plane (`tailscale up --ssh`) with firewall coupling.
2. Strong SSH validation/rollback and hardened sshd options.
3. Systemd service hardening directives (`NoNewPrivileges`, `ProtectSystem`, etc.).
4. Backdoor sshd separation model (we do not adopt by default).

Current gap impact:

1. Tailscale phase is missing in our implementation.
2. Service hardening directives are lighter than this source.
3. We do not yet expose a structured break-glass profile (intentional).

## 3. `stfurkan-claw-easy-setup`

Confirmed important patterns:

1. Reliable `sshd_config.d` drop-in model.
2. `sshd -t` validation and lockout-safe sequencing.
3. fail2ban jail config and unattended-upgrades activation.
4. Swap bootstrap and timesync setup.

Current gap impact:

1. Swap bootstrap not yet present.
2. Time/hostname/timezone system controls are not implemented.
3. Explicit fail2ban jail and unattended config management still partial.

## 4. `mundofacu-openclaw-vm-setup`

Confirmed important patterns:

1. Dedicated runtime user with temporary elevation and privilege revoke.
2. Swap bootstrap for low-memory hosts.
3. Optional VM/isolated egress concept.

Current gap impact:

1. Swap feature absent.
2. Optional isolated-egress profile absent.
3. We already implement dual-user least-privilege intent; this source reinforces it.

## 5. `eyal050-openclaw-remote-install`

Confirmed important patterns:

1. Strong phased orchestration and deep diagnostics.
2. Workspace backup/restore for reinstalls.
3. Remote wrapper mode and log collection.
4. Rich provider/channel helper ecosystem.

Current gap impact:

1. We do not have backup/restore workflow.
2. We do not have dedicated diagnose mode.
3. We do not have remote orchestrator wrapper.
4. This source also reinforces the need for strict defaults due to permissive upstream firewall/SSH behavior.

## 6. `phucmpham-deploy-openclaw`

Confirmed important patterns:

1. State-file resume behavior.
2. Rollback stack safety model.
3. Optional Tailscale operator flow.
4. BATS-oriented shell test discipline.

Current gap impact:

1. No state resume framework yet.
2. Rollback is currently mostly SSH-scoped, not full phase stack.
3. Tailscale still missing.
4. We use shell tests + Molecule, but not BATS.

## 7. `mortalezz-openclaw`

Confirmed important patterns:

1. `dbus-user-session` and user-systemd readiness handling.
2. Reboot-resume handling for kernel update flow.
3. Clear minimal-host caveat handling.

Current gap impact:

1. No reboot-resume support.
2. No host-profile-specific dbus/user-systemd checks.
3. This can affect edge-case reliability on minimal cloud images.

## 8. `custom-cloudflare-tunnel-traefik-openclaw` (preferred blueprint)

Confirmed important patterns:

1. Canonical edge topology and DNS helper contracts.
2. Global apps compose ownership and deployment helper model.
3. Mandatory policy injection and reporting.
4. Systemd services for edge and gateway.
5. Final validation checklist and demo deploy flow.

Current gap impact:

1. `openclaw-edge.service` and optional apps service still missing.
2. Final validation checklist not fully automated in runtime verify.
3. Hub auto-service pattern now added as a hard requirement and not yet implemented.

## 9. Cross-Cutting Missed Items (Consolidated)

P1 mandatory:

1. Tailscale baseline integration (now mandatory).
2. Hub service auto-creation after first app deploy.
3. Hub card click-through to real app URL (`https://<app>.<APPS_DOMAIN>`).
4. fail2ban/unattended explicit config + service management.
5. Hostname/timezone implementation.
6. Edge/apps systemd units.

P2/P3 important:

1. Docker socket proxy hardening.
2. MOTD operational status block.
3. Swap toggle/profile.
4. Resume/rollback framework beyond SSH.
5. Diagnose and backup/restore modes.
6. Optional host-profile conditionals for minimal images.

## 10. Conclusion

No research source was skipped in this second pass.  
The highest-impact deltas now are Tailscale mandatory integration and auto hub creation with real subdomain click-through, followed by baseline hardening and service lifecycle completion.
