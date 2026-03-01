# Project Handover: infra-ubuntu-2404-openclaw (Bash Toolkit)

Canonical architecture decision (source of truth): `docs/ARCHITECTURE_DECISION.md`.

This handover reflects the current implementation state after the Ansible-to-Bash migration.

## 1. Project Identity

- Repository: `infra-ubuntu-2404-openclaw`
- Local workspace path: `/Users/hendaz/Projects/Others/ubuntu-openclaw-server`
- Target OS: Ubuntu Server 24.04 LTS (noble)
- Primary implementation entrypoint: `scripts/install.sh`

## 2. Mission and Scope

The project provides repeatable, idempotent host automation for the OpenClaw hosting model:

1. Secure baseline on Ubuntu 24.04.
2. Dual-user model:
   - `hendaz` admin operator user (SSH + sudo)
   - `openclaw` runtime/service user (non-sudo)
3. SSH hardening:
   - port `1773`
   - `PermitRootLogin no`
   - `PasswordAuthentication no`
4. Edge and routing foundation:
   - Cloudflare Tunnel -> Traefik -> containers
   - no public app port publishing
5. OpenClaw runtime behind Traefik with mandatory workspace policy injection.
6. Global app registry/deploy helper contracts.
7. Reporting helper with channel delivery and stdout fallback.

## 3. Current Architecture Summary

- Top-level installer orchestrates modular phases under `scripts/lib/`.
- Config contract lives in `config/example.env` and is validated before phase execution.
- Artifacts and runtime paths default to `/opt/openclaw/*`.
- Networking contract uses shared Docker network `openclaw-edge`.
- DNS automation is Cloudflare API token driven.

## 4. Installer Phases (Implemented)

Execution order in `scripts/install.sh`:

1. `packages`
2. `user`
3. `ssh`
4. `firewall`
5. `edge`
6. `dns`
7. `openclaw`
8. `apps`
9. `report`
10. `verify`

Each phase is implemented in:

- `scripts/lib/packages.sh`
- `scripts/lib/user.sh`
- `scripts/lib/ssh.sh`
- `scripts/lib/firewall.sh`
- `scripts/lib/edge.sh`
- `scripts/lib/dns.sh`
- `scripts/lib/openclaw.sh`
- `scripts/lib/apps.sh`
- `scripts/lib/report.sh`
- `scripts/lib/verify.sh`

## 5. Configuration Contract

Required environment variables:

- `DOMAIN`
- `APPS_DOMAIN`
- `BOT_NAME`
- `TUNNEL_UUID`
- `CF_ZONE_ID`
- `CF_API_TOKEN`
- `OPENCLAW_GATEWAY_TOKEN`
- `OPENCLAW_GATEWAY_PASSWORD`
- `ADMIN_SSH_PUBLIC_KEY` or `ADMIN_SSH_PUBLIC_KEY_FILE`

Locked defaults enforced by validator:

- `ADMIN_USER=hendaz`
- `RUNTIME_USER=openclaw`
- `SSH_PORT=1773`
- `EDGE_NETWORK_NAME=openclaw-edge`
- `OPENCLAW_POLICY_INJECTION=true`

Config source:

- Template: `config/example.env`
- Runtime: `config/.env` (gitignored)

Validation command:

- `make check-config CONFIG_FILE=config/.env`

## 6. Generated Runtime Artifacts

Key managed files/directories include:

- Edge stack:
  - `/opt/openclaw/edge/docker-compose.yml`
  - `/opt/openclaw/edge/traefik/traefik.yml`
  - `/opt/openclaw/edge/cloudflared/config.yml`
- DNS helpers:
  - `/opt/openclaw/bin/cf_dns_ensure_wildcard.sh`
  - `/opt/openclaw/bin/cf_dns_upsert_subdomain.sh`
- OpenClaw runtime:
  - `/opt/openclaw/openclaw/config/openclaw.json`
  - `/opt/openclaw/openclaw/.env`
  - `/opt/openclaw/openclaw/docker-compose.yml`
  - `/opt/openclaw/openclaw/workspace/policies/deploy/AGENTS.md`
- Apps helpers:
  - `/opt/openclaw/apps/docker-compose.yml`
  - `/opt/openclaw/bin/register_app.py`
  - `/opt/openclaw/bin/deploy_app.sh`
- Reporting helper:
  - `/opt/openclaw/bin/report.sh`

## 7. Testing and Verification

### 7.1 Script Contract Tests

- Command: `make test-scripts`
- Coverage: deterministic phase-level dry-run and config assertions.

### 7.2 Molecule Scenarios (Bash-first)

- Docker scenario:
  - command: `make test-docker`
  - validates installer dry-run execution and config contract in `ubuntu:24.04` container
- Vagrant scenario:
  - command: `make test-vagrant`
  - validates live baseline install behavior in Ubuntu 24.04 VM while sandboxing SSH config path to avoid Molecule connectivity break

### 7.3 Lint

- command: `make lint`
- runs:
  - Bash syntax checks (`bash -n`)
  - YAML lint (`yamllint`)

## 8. CI Status

GitHub Actions workflow currently runs:

1. lint dependencies install
2. `make check-config CONFIG_FILE=config/example.env`
3. `make test-scripts`

Note:

- Molecule scenarios are validated locally and not currently run in CI.

## 9. Operational Quickstart

1. `python -m venv .venv && source .venv/bin/activate`
2. `make deps`
3. `make deps-test`
4. `cp config/example.env config/.env`
5. edit `config/.env`
6. `make check-config`
7. `make test-scripts`
8. optional local infra tests:
   - `make test-docker`
   - `make test-vagrant`
9. run install on target host:
   - `make run-install CONFIG_FILE=config/.env`

## 10. Known Gaps / Deferred Work

1. Tailscale workflow integration is not implemented yet in the Bash toolkit.
2. Multi-instance hosting support is deferred (single-instance contract currently).
3. Optional legacy scenario cleanup:
   - `molecule/default`
   - `molecule/vagrant-integration`
4. Optional CI expansion to include `make test-docker`.

## 11. Change Control Guidance

If another agent continues implementation:

1. Keep `docs/ARCHITECTURE_DECISION.md` as the canonical decision contract.
2. Keep `config/example.env` and `scripts/lib/config.sh` in lockstep.
3. Preserve locked security controls unless architecture decision is explicitly updated.
4. Add tests before enabling new feature flags in live phases.
