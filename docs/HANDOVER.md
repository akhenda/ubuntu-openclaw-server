# Project Handover: infra-ubuntu-2404-openclaw

## 1. Project Identity

- Repository name: `infra-ubuntu-2404-openclaw`
- Local path used during implementation: `/Users/hendaz/Projects/Others/ubuntu-openclaw-server`
- Primary branch: `main`
- Intended target OS: Ubuntu Server 24.04 LTS (noble)

## 2. Mission and Scope

This repository provides repeatable Ansible automation to prepare and operate Ubuntu 24.04 infrastructure for OpenClaw and related services.

It is designed to:

1. Bootstrap fresh Ubuntu hosts for Ansible management.
2. Apply a secure baseline (packages, updates, UFW, fail2ban, unattended-upgrades, MOTD, hostname).
3. Apply OS and SSH hardening via `devsec.hardening` collection roles.
4. Optionally integrate Cloudflare (origin CA trust, DNS records, SSL mode).
5. Optionally install and configure Oh My Zsh for an admin user (guru2 theme + git plugin).
6. Optionally deploy Docker socket proxy.
7. Optionally deploy Traefik reverse proxy foundation.
8. Optionally deploy Homepage dashboard hub.
9. Optionally install OpenClaw by running `openclaw/openclaw-ansible` locally on the target host.

## 3. Architecture at a Glance

- Ansible is the primary orchestration layer.
- `ansible/playbooks/site.yml` is the main orchestration playbook.
- Roles are modular and feature-gated using booleans from `group_vars`.
- Molecule is used for local validation across:
  - Docker scenario (fast base checks)
  - Vagrant scenario (full baseline/hardening)
  - Vagrant integration scenario (optional stack integration checks)

Core roles:

- `base`
- `hardening`
- `cloudflare`
- `socket_proxy`
- `traefik`
- `homepage`
- `openclaw`
- `oh_my_zsh`

## 4. Repository Control Surface

### 4.1 Make Targets

Defined in `Makefile`:

- `make deps`
- `make galaxy`
- `make lint`
- `make test-docker`
- `make test-vagrant`
- `make test-vagrant-integration`
- `make run-prod`
- `make run-vagrant`
- `make run-shell`
- `make run-socket-proxy`
- `make run-traefik`
- `make run-homepage`
- `make local-openclaw-up`
- `make local-openclaw-tunnel`
- `make local-openclaw-down`

### 4.2 Main Playbooks

- `ansible/playbooks/bootstrap.yml`: first-touch host bootstrap (python/sudo + optional admin/key)
- `ansible/playbooks/site.yml`: full stack application (role-based)
- Role wrapper playbooks exist for targeted runs (`base.yml`, `hardening.yml`, `openclaw.yml`, etc.)

## 5. Security Model Implemented

Default intended production posture:

- SSH password auth disabled.
- Root SSH login disabled.
- SSH port defaults to `1773`.
- UFW enabled with default deny incoming and allow outgoing.
- Only configured SSH port(s) opened.
- Legacy port 22 denied when not explicitly allowed.
- `fail2ban` enabled for SSH.
- `unattended-upgrades` enabled for security updates.

Important behavior:

- Baseline firewall management auto-defers when `openclaw_enable=true` to avoid fighting upstream OpenClaw firewall behavior.

## 6. Configuration Model

Primary variable source:

- `ansible/group_vars/all.yml` (gitignored, created from `all.yml.example`)

Secrets and sensitive values are expected from:

- Environment variables and/or Ansible Vault files

Common env vars used by defaults:

- `INFRA_ADMIN_USER`
- `INFRA_ADMIN_SSH_PUBLIC_KEY`
- `INFRA_ADMIN_PASSWORD`
- `INFRA_ADMIN_PASSWORD_HASH`
- `INFRA_FQDN`
- `INFRA_HOST_IP`
- `CLOUDFLARE_ZONE_ID`
- `CLOUDFLARE_ZONE_NAME`
- `CLOUDFLARE_EMAIL`
- `CLOUDFLARE_GLOBAL_API_KEY`
- `CLOUDFLARE_DNS_API_TOKEN`

## 7. Role-by-Role Notes

### 7.1 base role

Responsibilities:

- apt cache/upgrade handling
- baseline package installation
- optional admin user creation + SSH key installation
- optional removal of default `ubuntu` user
- timezone and hostname management
- custom MOTD script install
- unattended-upgrades config
- fail2ban config/service
- UFW defaults and SSH rules

### 7.2 hardening role

Includes upstream:

- `devsec.hardening.os_hardening`
- `devsec.hardening.ssh_hardening`

Overrides tuned for key-only auth and root-login disable.

### 7.3 cloudflare role

Supports:

- install Cloudflare Origin CA root cert in system trust
- DNS upsert via `community.general.cloudflare_dns`
- SSL mode enforcement via Cloudflare API

Auth model:

- API token preferred (`cloudflare_dns_api_token`)
- Global API key fallback requires `cloudflare_email`

### 7.4 socket_proxy role

Deploys `tecnativa/docker-socket-proxy` with constrained API exposure.

Notable reliability tuning:

- apt operations use configurable `socket_proxy_apt_lock_timeout` (defaults from `apt_lock_timeout`, fallback 600)

### 7.5 traefik role

Deploys Traefik stack with:

- Docker provider
- optional socket proxy endpoint
- optional origin cert/key file provisioning
- optional dashboard host
- optional UFW open for 80/443 (when appropriate)

### 7.6 homepage role

Deploys Homepage dashboard with Traefik labels and optional socket proxy Docker endpoint for container discovery.

### 7.7 oh_my_zsh role

For target user:

- installs zsh
- installs Oh My Zsh
- installs `guru2` theme
- installs `z.sh`
- renders `.zshrc`
- sets default shell to `/bin/zsh`

### 7.8 openclaw role

Implements local-target OpenClaw install pattern:

1. install prerequisites on target
2. clone `openclaw/openclaw-ansible`
3. render `openclaw-vars.yml`
4. run `ansible-galaxy collection install -r requirements.yml`
5. run `ansible-playbook playbook.yml -e @openclaw-vars.yml`

Also supports policy bootstrap files/hooks for Traefik routing conventions.

Additional compatibility variables introduced:

- `openclaw_ci_test`
- `openclaw_disable_vboxadd_hooks`
- `openclaw_bootstrap_pnpm`

## 8. Testing and Validation Strategy

### 8.1 Docker Molecule

- Fast baseline checks.
- Verifies key baseline packages installed.

### 8.2 Vagrant Molecule

- Full site run without OpenClaw.
- Includes idempotence + verify.

### 8.3 Vagrant Integration Molecule

- Full site with optional stack pieces enabled for integration assertions:
  - socket proxy
  - traefik
  - homepage
  - oh-my-zsh
- Additional verify checks around SSH, UFW, MOTD, service state.

Reliability hardening applied:

- apt lock timeout tuning in playbooks/scenarios
- idempotence-friendly mode for socket proxy compose in integration scenario

## 9. CI Behavior

GitHub workflow (`.github/workflows/ci.yml`):

- install Python dependencies
- install Ansible collections
- run `ansible-lint`
- run `molecule test -s docker`

Vagrant scenarios are intentionally not run in CI.

## 10. Local OpenClaw "Real Run" Path (Persistent VM)

Implemented helper flow:

1. `make local-openclaw-up`
   - destroys existing vagrant-integration instance
   - creates fresh one
   - converges with `molecule/vagrant-integration/local-openclaw.vars`
2. `make local-openclaw-tunnel`
   - SSH local forward from host to VM for `OPENCLAW_UI_PORT` (default `3000`)
3. `make local-openclaw-down`
   - destroy local VM

Profile file:

- `molecule/vagrant-integration/local-openclaw.vars`

Current local profile intent:

- OpenClaw enabled
- Cloudflare/Traefik/Homepage/socket proxy disabled for focused OpenClaw bring-up
- hardening disabled for local convenience
- SSH kept on port 22 locally
- optional compatibility toggles enabled for VirtualBox and pnpm bootstrap

## 11. Work Completed Across Major Iterations

Key milestones reflected in commit history:

- Traefik role foundation
- Homepage role and runbook
- OpenClaw bootstrap policy hook integration
- Docker socket proxy role
- Oh My Zsh role
- Vagrant integration scenario and verification expansion
- apt lock/idempotence stabilization
- local OpenClaw persistent-run profile + compatibility toggles

Recent notable commits:

- `4c5af2d` apt lock hardening for socket proxy installs
- `65d7fa7` local-openclaw profile and installer compatibility toggles

## 12. Known Gaps / Caveats at Handover

1. Molecule tests are stable for defined test scenarios.
2. Local persistent OpenClaw run remains the most environment-sensitive path due to upstream installer behavior and VM-specific package/service interactions.
3. Upstream `openclaw-ansible` can be long-running with sparse output during apt/package phases.
4. Do not assume silent periods mean deadlock; verify from inside VM before aborting.

## 13. Agent Handover Checklist (Recreate + Continue)

If another agent is recreating/continuing this project, they must:

1. Install deps and collections:
   - `make deps`
   - `make galaxy`
2. Validate baseline quality:
   - `make lint`
   - `make test-docker`
   - `make test-vagrant`
   - `make test-vagrant-integration`
3. Create `ansible/group_vars/all.yml` from example and configure required values.
4. For production:
   - update `ansible/inventories/prod/hosts.ini`
   - run bootstrap if needed
   - run `make run-prod`
5. For local OpenClaw UI:
   - run `make local-openclaw-up`
   - run `make local-openclaw-tunnel`
   - open `http://127.0.0.1:3000`
6. If local OpenClaw run fails:
   - inspect `/opt/openclaw-ansible` logs/tasks inside VM
   - verify `node`, `npm`, `pnpm`, and `openclaw` availability
   - verify SSH/firewall accessibility assumptions in local profile

## 14. Non-Negotiable Project Principles

- Keep automation idempotent and deterministic where feasible.
- Keep production security defaults strict (key-only auth, root login off, firewall restricted).
- Keep secrets out of git.
- Prefer variable-driven behavior over ad-hoc hardcoding.
- Isolate local-development workarounds in local profile variables.

