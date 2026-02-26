# infra-ubuntu-2404-openclaw

Repeatable, idempotent infrastructure automation for **Ubuntu Server 24.04 LTS (noble)** using Ansible.

This repository bootstraps a fresh host, applies a secure baseline, applies DevSec hardening roles, and can optionally install OpenClaw by running `openclaw/openclaw-ansible` **locally on the target host**.

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
4. Optionally installs OpenClaw by cloning and running `openclaw/openclaw-ansible` **on the target host**.

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

## OpenClaw Behavior

When `openclaw_enable: true`, the `openclaw` role:

1. Installs prerequisites on the target host (`git`, `ansible-core`).
2. Clones `openclaw/openclaw-ansible` to `/opt/openclaw-ansible` (default).
3. Runs `ansible-galaxy collection install -r requirements.yml` in that directory.
4. Runs `ansible-playbook playbook.yml -e @openclaw-vars.yml` in that directory as root.

At a high level, OpenClaw installer can set up components such as optional Tailscale, UFW + fail2ban + unattended-upgrades, Docker, Node/pnpm, and an OpenClaw systemd service.

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

`openclaw_enable` defaults to `false` so Molecule runs are deterministic.
