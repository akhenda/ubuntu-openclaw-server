# Research Note: `eyal050/openclaw-remote-install`

Reference:
- Repo: `https://github.com/eyal050/openclaw-remote-install`
- Primary script: `unified-install-openclaw.sh` (v2.0.0)
- Context: `README.md`, `.env.remote.template`, `TELEGRAM-PAIRING.md`, `WORKSPACE-FIX.md`, legacy installer + helper scripts

## Snapshot of Approach

A large, feature-rich Bash framework focused on Docker-based OpenClaw deployment with both local and remote execution modes.

Major capabilities:
1. Local and remote installation via single unified script.
2. SSH auth options for remote mode (password via `sshpass` or key-based).
3. OpenClaw source clone/build + Docker Compose deployment.
4. Multi-provider auth profile generation (Anthropic/OpenAI/Gemini/Codex).
5. Telegram setup and optional automated pairing workflow.
6. Workspace backup/restore for reinstall scenarios.
7. Built-in diagnostics and troubleshooting checks.
8. UFW enablement with optional source restriction (`UFW_ALLOW_FROM`).

## What It Does Well

1. Strong installer architecture.
- Clear phased execution model.
- Extensive argument/env support.
- Robust logging (`install` + `extended` logs) and diagnostics.

2. Operational maturity.
- Handles reinstall cleanup + optional workspace preservation.
- Includes helper scripts for pairing/workspace fixes/verification.

3. Remote automation coverage.
- End-to-end remote execution flow (validate server, transfer script/env, execute, fetch logs).

4. Good developer ergonomics.
- Supports both interactive and non-interactive invocation styles.
- Comprehensive README/runbook coverage.

## Risks / Tradeoffs

1. Security defaults conflict with our baseline.
- Default gateway bind is `lan` (not loopback).
- Config sets `allowInsecureAuth: true` by default.
- Firewall config allows SSH on port `22` and opens gateway port externally by default.

2. SSH hardening is mostly absent.
- No enforcement of `PermitRootLogin no`, `PasswordAuthentication no`, custom SSH port, or fail2ban baseline in main flow.

3. Secrets handling risk.
- API keys and tokens written into `.env` files and transferred for remote mode.
- Password-based SSH mode supported and encourages `sshpass` use.

4. Convergence and blast radius.
- Large monolithic script with many responsibilities increases change risk.
- Heavy Docker source build path may be slow/fragile on small hosts.

5. OpenClaw install model divergence.
- Uses Dockerized source deployment path instead of local target-host ansible installer pattern we previously evaluated.

## Keep / Modify / Reject for Our Toolkit

Keep:
1. Phased installer structure and logging discipline.
2. Diagnostics-first mindset and post-install verification checks.
3. Workspace preservation/backup pattern.
4. Optional remote orchestration concept (can become a wrapper around our core local installer).

Modify:
1. Security defaults:
- force loopback gateway by default
- disable insecure auth defaults
- do not expose gateway port publicly unless explicitly requested

2. Host baseline controls:
- add SSH hardening (`1773`, root login off, password auth off)
- add fail2ban, unattended-upgrades, hostname/user policy

3. Secrets handling:
- avoid plaintext password workflows by default
- prefer key-based remote auth and vault/env-file protections

4. Firewall model:
- align to our explicit policy profiles (baseline host + reverse proxy modes)

Reject (as defaults):
1. `OPENCLAW_GATEWAY_BIND=lan` with internet-reachable dashboard posture.
2. `allowInsecureAuth: true` as baseline setting.
3. Password-based SSH remote mode as recommended default.

## Useful Ideas to Port

1. Borrow structured phase orchestration and extended logging style.
2. Add a dedicated `--diagnose` mode to our toolkit.
3. Add optional workspace backup/restore hooks.
4. Add optional helper workflows for channel pairing automation as separate scripts.

## Mapping to `plans/APPROVED_BASE_PLAN.md`

Supports:
1. Step 1 (framework): excellent template for module orchestration and CLI surface.
2. Step 4 (OpenClaw core): strong verification and troubleshooting patterns.
3. Step 8 (docs/control surface): very good operator-facing runbook quality.

Divergences we keep intentionally:
1. Our baseline remains secure-by-default (loopback, no insecure auth, strict SSH baseline).
2. We prioritize key-only access and non-interactive secure flows for production automation.
3. We separate host hardening concerns from OpenClaw app deployment concerns more explicitly.
