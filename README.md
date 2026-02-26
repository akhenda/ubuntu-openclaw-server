# infra-ubuntu-2404-openclaw

Repeatable, idempotent infrastructure automation for **Ubuntu Server 24.04 LTS (noble)** using Ansible.

This repository bootstraps a fresh host, applies a secure baseline, applies DevSec hardening roles, can manage Cloudflare DNS/SSL settings, can configure Oh My Zsh for your admin user, can deploy a Docker socket proxy, can deploy a Traefik reverse-proxy foundation, can deploy a Homepage hub service, and can optionally install OpenClaw by running `openclaw/openclaw-ansible` **locally on the target host**.

## What This Repo Does

1. Bootstraps a fresh Ubuntu 24.04 server for Ansible management.
2. Applies secure baseline configuration:
- package updates and baseline packages
- UFW firewall baseline (default deny incoming, allow outgoing, allow SSH)
- unattended security updates
- fail2ban for SSH
- hostname management from config/env
- custom MOTD with OpenClaw and system status summary
3. Applies OS + SSH hardening using `devsec.hardening` collection roles:
- `devsec.hardening.os_hardening`
- `devsec.hardening.ssh_hardening`
4. Optionally applies Cloudflare setup:
- install Cloudflare Origin CA root cert on the server trust store
- manage Cloudflare DNS records (token/global-key auth)
- enforce Cloudflare SSL mode (for example `strict`)
5. Optionally configures Oh My Zsh for the admin user:
- installs `zsh` and Oh My Zsh
- installs `guru2` theme
- enables `git` plugin
- sets `zsh` as default shell
6. Optionally deploys Docker socket proxy:
- deploys `tecnativa/docker-socket-proxy` with restricted Docker API permissions
- keeps Docker socket off Traefik/Homepage containers by default when enabled
- publishes proxy port to host only if explicitly enabled
7. Optionally deploys Traefik foundation:
- install Docker engine + compose plugin
- create shared `proxy` docker network
- deploy Traefik stack on `80/443` with Docker provider `exposedByDefault=false`
- optionally configure dashboard host and Cloudflare origin cert files
8. Optionally deploys Homepage hub behind Traefik:
- deploy Homepage stack at `/opt/homepage`
- route `hub.<domain>` via Traefik labels on the container
- use socket proxy endpoint for Homepage Docker integration (or unix socket if socket proxy is disabled)
9. Optionally installs OpenClaw by cloning and running `openclaw/openclaw-ansible` **on the target host**.

## Controller Prerequisites

- Python **3.11+** recommended
- `venv` available
- Ansible/Molecule tooling installed from `requirements.txt`
- Docker installed (for Molecule docker scenario)
- Vagrant + provider installed (VirtualBox or libvirt; default in this repo is VirtualBox)

## Target Prerequisites

- Ubuntu Server **24.04 LTS** reachable via SSH
- Admin user with sudo privileges

## Quickstart

```bash
python -m venv .venv && source .venv/bin/activate
make deps && make galaxy && make lint
make test-docker
make test-vagrant
make test-vagrant-integration
```

## Production Run

1. Edit `ansible/inventories/prod/hosts.ini` with your real host/user details.
2. Copy `ansible/group_vars/all.yml.example` to `ansible/group_vars/all.yml` (this file is gitignored) and set values, or use Ansible Vault.
3. Run:

```bash
make run-prod
```

## SSH and User Model

- SSH hardening defaults:
  - SSH runs on port `1773`
  - root login disabled
  - password login disabled (key-only)
- Firewall defaults:
  - deny incoming by default
  - only configured SSH port(s) are allowed
  - port `22` is denied when not explicitly allowed
- Admin user defaults:
  - created as sudo user from env-configurable values
  - default Ubuntu bootstrap user (`ubuntu`) can be removed

Environment variables supported by defaults:

- `INFRA_ADMIN_USER`
- `INFRA_ADMIN_SSH_PUBLIC_KEY`
- `INFRA_ADMIN_PASSWORD` (optional)
- `INFRA_ADMIN_PASSWORD_HASH` (optional, preferred over plain password)
- `INFRA_FQDN` (optional; if set, hostname + hosts mapping are managed)
- `INFRA_HOST_IP` (optional; override detected primary host IP for `/etc/hosts` + MOTD)

Example:

```bash
export INFRA_ADMIN_USER=openclaw
export INFRA_ADMIN_SSH_PUBLIC_KEY=\"ssh-ed25519 AAAA...you@example\"
```

## Oh My Zsh

The `oh_my_zsh` role configures a consistent shell environment for your admin user.

Behavior:

- installs `zsh`
- clones Oh My Zsh
- installs the `guru2` theme
- installs `z.sh` helper (optional)
- renders `.zshrc` with `git` plugin
- sets `/bin/zsh` as default shell

Example:

```yaml
oh_my_zsh_enable: true
oh_my_zsh_target_user: "{{ base_admin_user }}"
oh_my_zsh_theme_name: guru2
oh_my_zsh_plugins:
  - git
```

Run only shell setup:

```bash
ansible-playbook -i ansible/inventories/prod/hosts.ini ansible/playbooks/oh_my_zsh.yml
# or
make run-shell
```

## Cloudflare Setup (Traefik-Friendly)

The `cloudflare` role is designed to support hub + wildcard routing patterns like:

- `hub.akhenda.net` -> VPS IP (A record, proxied)
- `*.akhenda.net` -> `hub.akhenda.net` (CNAME wildcard, proxied)
- SSL mode forced to `Full (strict)` via Cloudflare API (`cloudflare_ssl_mode: strict`)

Key variables:

- `cloudflare_zone_id`
- `cloudflare_global_api_key`
- `cloudflare_dns_api_token` (recommended)

Recommended auth model:

- use `cloudflare_dns_api_token` (Bearer token) instead of global API key
- if using `cloudflare_global_api_key`, set `cloudflare_email` too

Example:

```yaml
cloudflare_enable: true
cloudflare_manage_dns: true
cloudflare_manage_ssl_mode: true
cloudflare_ssl_mode: strict

cloudflare_zone_name: akhenda.net
cloudflare_zone_id: "YOUR_ZONE_ID"
cloudflare_dns_api_token: "{{ vault_cloudflare_dns_api_token }}"

cloudflare_dns_records:
  - record: hub
    type: A
    value: 185.185.80.175
    proxied: true
  - record: "*"
    type: CNAME
    value: hub.akhenda.net
    proxied: true
```

Cloudflare Access policy setup (`*.akhenda.net` allowlist by email) remains a manual dashboard step and should be applied after DNS/SSL are in place.

Cloudflare Access click-path (dashboard):

1. `Zero Trust` -> `Access` -> `Applications` -> `Add an application`.
2. Choose `Self-hosted`.
3. Set `Application domain` to `*.akhenda.net` (or `hub.akhenda.net` first if you prefer phased rollout).
4. Add an `Allow` policy:
- Include your approved emails (for example your Google/GitHub identity emails).
- Keep default deny for everyone else.
5. Save and test in an incognito browser to confirm authentication is enforced.

## Docker Socket Proxy

The `socket_proxy` role deploys a hardened Docker API proxy for other services that need Docker metadata access.

Behavior:

- deploys stack under `/opt/docker-socket-proxy`
- runs `tecnativa/docker-socket-proxy`
- defaults to no host port publishing (`socket_proxy_publish_port: false`)
- exposes only a constrained set of Docker API endpoints (override with `socket_proxy_env_overrides`)

Example:

```yaml
socket_proxy_enable: true
socket_proxy_endpoint: "http://docker-socket-proxy:2375"
socket_proxy_compose_idempotence_mode: false
socket_proxy_env_overrides:
  CONTAINERS: "1"
  IMAGES: "1"
  INFO: "1"
  NETWORKS: "1"
  EVENTS: "1"
```

Run only socket proxy:

```bash
ansible-playbook -i ansible/inventories/prod/hosts.ini ansible/playbooks/socket_proxy.yml
# or
make run-socket-proxy
```

## Traefik Foundation

The `traefik` role is designed to prepare the VPS for an app-hub model (for example `hub.akhenda.net` and `*.akhenda.net`) without touching existing OpenClaw containers.

Behavior:

- installs Docker + compose plugin and ensures docker service is running
- adds configured admin user to docker group
- creates `proxy` network for shared reverse-proxy routing
- deploys Traefik stack at `/opt/traefik`
- uses `traefik_docker_endpoint` (socket proxy endpoint by default when enabled)
- opens UFW `80/443` when firewall management is enabled in this repo
- supports Cloudflare origin certificate via vars (`traefik_origin_cert_content`, `traefik_origin_key_content`) or pre-existing files under `/opt/traefik/certs`

Example:

```yaml
traefik_enable: true
traefik_domain: akhenda.net
traefik_dashboard_enable: true
traefik_dashboard_host: traefik.akhenda.net
traefik_use_origin_cert: true
traefik_origin_cert_content: "{{ vault_traefik_origin_cert }}"
traefik_origin_key_content: "{{ vault_traefik_origin_key }}"
```

Run only Traefik:

```bash
ansible-playbook -i ansible/inventories/prod/hosts.ini ansible/playbooks/traefik.yml
# or
make run-traefik
```

## Homepage Hub

The `homepage` role deploys the Homepage dashboard behind Traefik and routes it through `hub.<domain>`.

Behavior:

- deploys stack under `/opt/homepage`
- uses docker network `proxy` (or your configured Traefik network)
- adds Traefik labels for `Host(\`hub.<domain>\`)` on `websecure`
- uses `homepage_docker_proxy_endpoint` for Docker integration (socket proxy by default when enabled)

Example:

```yaml
homepage_enable: true
homepage_domain: akhenda.net
homepage_host: hub.akhenda.net
```

Run only Homepage:

```bash
ansible-playbook -i ansible/inventories/prod/hosts.ini ansible/playbooks/homepage.yml
# or
make run-homepage
```

Reusable app compose snippet (for OpenClaw-generated or custom services):

```yaml
services:
  myapp:
    image: ghcr.io/acme/myapp:latest
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.myapp.rule=Host(`myapp.akhenda.net`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls=true"
      - "traefik.http.services.myapp.loadbalancer.server.port=3000"

networks:
  proxy:
    external: true
```

## OpenClaw Behavior

When `openclaw_enable: true`, the `openclaw` role:

1. Installs prerequisites on the target host (`git`, `ansible-core`).
2. Clones `openclaw/openclaw-ansible` to `/opt/openclaw-ansible` (default).
3. Runs `ansible-galaxy collection install -r requirements.yml` in that directory.
4. Runs `ansible-playbook playbook.yml -e @openclaw-vars.yml` in that directory as root.
5. Optionally manages OpenClaw bootstrap policy files in the OpenClaw workspace and configures the `bootstrap-extra-files` hook so OpenClaw always receives Traefik routing guardrails.

At a high level, OpenClaw installer can set up components such as optional Tailscale, UFW + fail2ban + unattended-upgrades, Docker, Node/pnpm, and an OpenClaw systemd service.

### OpenClaw Traefik Policy Injection

When `openclaw_manage_bootstrap_policy: true` (default), this repo:

- creates policy files at `~/.openclaw/workspace/bootstrap/openclaw-traefik/AGENTS.md` and `SOUL.md` for `openclaw_cli_user`
- configures OpenClaw workspace path to `~/.openclaw/workspace`
- enables `hooks.internal.entries.bootstrap-extra-files`
- sets hook paths to:
  - `bootstrap/openclaw-traefik/AGENTS.md`
  - `bootstrap/openclaw-traefik/SOUL.md`

This gives OpenClaw a repeatable routing contract for Traefik labels/networking whenever new app tasks are bootstrapped.

You can validate on target:

```bash
openclaw config get agents.defaults.workspace
openclaw config get hooks.internal.entries.bootstrap-extra-files.enabled
openclaw config get hooks.internal.entries.bootstrap-extra-files.paths
openclaw hooks check
```

## Post-Install Manual Steps (Human)

This repo does **not** run interactive onboarding. After installation, connect to the server and run the OpenClaw CLI/manual steps you need, for example:

- `openclaw configure`
- provider logins/auth flows
- optional `openclaw onboard`

## Secrets and Safe Variables

- Example shared vars live in `ansible/group_vars/all.yml.example`.
- Keep real secrets (for example `tailscale_authkey`) in:
  - `ansible/group_vars/all.yml` (gitignored), or
  - encrypted Ansible Vault files.

Example Vault usage:

```bash
ansible-vault create ansible/group_vars/vault.yml
ansible-playbook -i ansible/inventories/prod/hosts.ini ansible/playbooks/site.yml --ask-vault-pass
```

## Molecule Scenarios

- `docker` scenario: quick base role checks on `ubuntu:24.04` container.
- `vagrant` scenario: full `site.yml` (with `openclaw_enable=false`) on Ubuntu 24.04 VM.
- `vagrant-integration` scenario: full `site.yml` with optional roles enabled (`socket_proxy`, `traefik`, `homepage`, `oh_my_zsh`) plus SSH/firewall policy checks (`1773` allowed, `22` denied).

`openclaw_enable` defaults to `false` so Molecule runs are deterministic.

Idempotence and lock-handling notes:

- All role wrapper playbooks set `ansible.builtin.apt` `lock_timeout` via `module_defaults`; default is `apt_lock_timeout=300` seconds.
- `vagrant-integration` sets `os_sysctl_enabled: false` and `os_chmod_home_folders: false` to avoid known non-idempotent behavior in upstream `devsec.hardening.os_hardening` on ephemeral VMs.
- `vagrant-integration` sets `socket_proxy_compose_idempotence_mode: true` so the socket proxy compose step does not fail Molecule idempotence checks due to Docker Compose v2 changed reporting.
