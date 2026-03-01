# Research Note: `PhucMPham/deploy-openclaw`

Reference:
- Repo: `https://github.com/PhucMPham/deploy-openclaw`
- Primary script: `scripts/deploy-openclaw.sh`
- Context: `README.md`, `LICENSE`, and upstream `tests/` suite

## Snapshot of Approach

An interactive Bash TUI wizard (with `gum`/`fzf` fallbacks) for Ubuntu/Debian VPS deployment, focused on guided safety and resumable state.

Core flow:
1. System checks and environment detection.
2. Creates dedicated `openclaw` user and `/opt/openclaw` workspace.
3. Optional security tasks selected interactively: UFW, SSH key setup, SSH hardening, fail2ban, Tailscale.
4. Installs Docker + Node (via NVM) + OpenClaw CLI.
5. Hands off to interactive `openclaw onboard --install-daemon`.
6. Persists deployment progress in a state file to resume after disconnect/failure.

## What It Does Well

1. Excellent operator UX for manual setup.
- TUI-driven flow, clear prompts, and safer staged choices.

2. Good safety guardrails.
- SSH hardening is blocked until SSH keys are confirmed.
- Includes sshd config backup and syntax validation rollback.

3. Strong resilience concept.
- State persistence (`/opt/openclaw/.deploy-state`) enables resume behavior.

4. Better testing culture than many comparable scripts.
- Includes BATS unit/integration tests and Dockerized test runner in upstream repo.

## Risks / Tradeoffs

1. Highly interactive by design.
- Not ideal for deterministic non-interactive infrastructure automation pipelines.

2. Security defaults do not match our baseline.
- UFW setup allows `ssh` + `80` + `443` by default.
- SSH hardening uses `PermitRootLogin prohibit-password` (root key login still allowed).
- No enforced custom SSH port (our target is `1773`).

3. OpenClaw provisioning remains interactive.
- Relies on human-driven `openclaw onboard` session.

4. Scope gaps for our architecture.
- No Cloudflare automation, no Traefik/socket-proxy integration, no hostname policy layer, no env-driven admin-user model.

## Keep / Modify / Reject for Our Toolkit

Keep:
1. Safety-gated SSH hardening pattern (verify keys before lock-down).
2. Rollback and validation approach for critical SSH changes.
3. State persistence/resume design.
4. Testing discipline (BATS + containerized test runner ideas).

Modify:
1. Access/security defaults:
- enforce `Port 1773`
- enforce `PermitRootLogin no`
- enforce `PasswordAuthentication no`
- use env-driven admin user/key model

2. Firewall policy:
- avoid blanket opening `80/443` unless required by enabled features (e.g., Traefik)

3. Execution model:
- provide non-interactive default mode for automation while preserving optional interactive mode

4. OpenClaw integration:
- use our final deterministic install/config path and explicit health verification

Reject (as defaults):
1. Root key-based SSH allowance.
2. Interactive-only control plane for base provisioning.
3. Implicit web-port exposure in baseline security setup.

## Useful Ideas to Port

1. Add `state_file` + resume support to our Bash framework.
2. Add pre-flight + post-change "safety gates" for risky steps.
3. Add BATS-based shell test coverage for core modules (state, ssh, firewall, error-handling).
4. Keep rollback stack pattern for critical system changes.

## Mapping to `plans/APPROVED_BASE_PLAN.md`

Supports:
1. Step 1 (framework): strong modular UX and rollback/state ideas.
2. Step 2 (access lockdown): mature safety-check mechanics before SSH hardening.
3. Step 7 (testing): concrete test architecture we can adapt to our Molecule/Vagrant pipeline.

Divergences we keep intentionally:
1. Our baseline remains strict (`1773`, key-only, no root SSH login).
2. Our default execution path is non-interactive and reproducible.
3. We integrate Cloudflare/Traefik/socket-proxy and other host baseline features not covered upstream.
