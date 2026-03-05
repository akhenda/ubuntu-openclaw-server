# infra-ubuntu-2404-openclaw

Bash-first, idempotent Ubuntu 24.04 server setup toolkit for OpenClaw edge hosting.

This repository implements the architecture in [docs/ARCHITECTURE_DECISION.md](docs/ARCHITECTURE_DECISION.md):

1. Secure host baseline (`hendaz` admin + `openclaw` runtime, SSH on `1773`, no root login, no password auth)
2. Mandatory Tailscale baseline (`tailscaled` + `tailscale up` with idempotence/test-mode guard)
3. Socket-proxy-hardened Cloudflare Tunnel + Traefik edge stack on `openclaw-edge`
4. OpenClaw host runtime (non-Docker) + mandatory workspace policy injection (`bootstrap-extra-files`)
5. Global apps registry helpers with hub auto-create during install (and ensured on deploy)
6. Systemd lifecycle units, MOTD status script, Oh-My-Zsh setup, reporting helper, and verification

## Current State

Entrypoint:

- `scripts/install.sh`

Phase order:

1. `packages`
2. `system`
3. `user`
4. `ssh`
5. `firewall`
6. `tailscale`
7. `socket_proxy`
8. `edge`
9. `dns`
10. `openclaw`
11. `apps`
12. `systemd`
13. `motd`
14. `oh_my_zsh`
15. `report`
16. `verify`

## Prerequisites

Controller machine:

1. Python 3.11+ (recommended)
2. `venv`
3. Optional dependency profiles:
   - `requirements-test.txt` (Molecule)
   - `requirements-lint.txt` (yamllint)
   - `requirements-dev.txt` (full profile)
4. Docker (for `molecule/docker`)
5. Vagrant + provider (VirtualBox/libvirt) (for `molecule/vagrant`)

Target machine:

1. Ubuntu Server 24.04 LTS
2. Initial sudo-capable access user

## Quickstart

```bash
python -m venv .venv && source .venv/bin/activate
make deps
make deps-test
make lint
cp config/example.env config/.env
$EDITOR config/.env
make check-config
make test-scripts
make test-docker
make test-vagrant
make run-install
```

## Make Targets

- `make deps`: alias of `make deps-dev`
- `make deps-dev`: install `requirements-dev.txt`
- `make deps-test`: install `requirements-test.txt`
- `make deps-lint`: install `requirements-lint.txt`
- `make lint`: bash syntax + yamllint
- `make check-config`: validate `config/.env` and print effective config
- `make run-install`: execute full installer
- `make test-scripts`: run Bash phase tests
- `make test-docker`: run Molecule docker scenario
- `make test-vagrant`: run Molecule vagrant scenario

## Configuration

Copy `config/example.env` to `config/.env`.

Required core values:

1. `DOMAIN`
2. `APPS_DOMAIN`
3. `BOT_NAME`
4. `HOST_FQDN`
5. `TUNNEL_UUID`
6. `CF_ZONE_ID`
7. `CF_API_TOKEN`
8. `TAILSCALE_AUTHKEY`
9. `OPENCLAW_GATEWAY_TOKEN`
10. `OPENCLAW_GATEWAY_PASSWORD`
11. `ADMIN_SSH_PUBLIC_KEY` or `ADMIN_SSH_PUBLIC_KEY_FILE`
12. Optional: `ADMIN_USER_PASSWORD_HASH` (for local `sudo -i` password prompt)

Hub contract defaults:

1. `HUB_ENABLE=true`
2. `HUB_AUTOCREATE_ON_FIRST_APP=true`
3. `HUB_PRIMARY_HOST=hub.<APPS_DOMAIN>`
4. `HUB_ALIAS_HOST=apps.<DOMAIN>`
5. App cards link to `https://<app>.<APPS_DOMAIN>`

Mission Control default app:

1. `MISSION_CONTROL_ENABLE=true`
2. `MISSION_CONTROL_HOST=mission-control.<APPS_DOMAIN>` (frontend)
3. `MISSION_CONTROL_API_HOST=mission-control-api.<APPS_DOMAIN>` (backend API)
4. `MISSION_CONTROL_AUTH_MODE=local` with `MISSION_CONTROL_LOCAL_AUTH_TOKEN` (50+ chars)
5. Installer syncs `abhi1693/openclaw-mission-control` to `${APPS_ROOT_DIR}/mission-control-src`
6. Services are managed in apps compose:
   `mission-control-db`, `mission-control-redis`, `mission-control-backend`, `mission-control`, `mission-control-webhook-worker`
7. Frontend and backend routes are exposed via Traefik and frontend card appears in Hub

Tailscale test-mode:

1. `TAILSCALE_ALLOW_PLACEHOLDER_AUTHKEY=false` by default
2. Set `true` only in deterministic test fixtures with placeholder keys

Locked defaults:

1. `ADMIN_USER=hendaz`
2. `RUNTIME_USER=openclaw`
3. `SSH_PORT=1773`
4. `EDGE_NETWORK_NAME=openclaw-edge`
5. `OPENCLAW_POLICY_INJECTION=true`

Reporting owner is configurable via `REPORT_OWNER_NAME` (default `Joseph`).

## Generated Artifacts

1. Edge stack:
- `/opt/openclaw/edge/traefik/traefik.yml`
- `/opt/openclaw/edge/cloudflared/config.yml`
- `/opt/openclaw/edge/docker-compose.yml`

2. DNS helpers:
- `/opt/openclaw/bin/cf_dns_ensure_wildcard.sh`
- `/opt/openclaw/bin/cf_dns_upsert_subdomain.sh`

3. System baseline:
- `/etc/hostname`
- `/etc/hosts`
- `/etc/apt/apt.conf.d/50unattended-upgrades`
- `/etc/apt/apt.conf.d/20auto-upgrades`
- `/etc/fail2ban/jail.d/openclaw.local`

4. OpenClaw runtime:
- `/home/openclaw/.openclaw/openclaw.json`
- `/opt/openclaw/openclaw/.env`
- `/home/openclaw/.openclaw/workspace/policies/deploy/AGENTS.md`
- `/usr/local/bin/openclaw` (wrapper)

5. Apps/hub helpers:
- `/opt/openclaw/apps/docker-compose.yml`
- `/opt/openclaw/bin/register_app.py`
- `/opt/openclaw/bin/ensure_hub.sh`
- `/opt/openclaw/bin/deploy_app.sh`
- `/opt/openclaw/apps/mission-control-src` (Mission Control source checkout when enabled)

6. Systemd units:
- `/etc/systemd/system/openclaw-edge.service`
- `/etc/systemd/system/openclaw-gateway.service` (when enabled)
- `/etc/systemd/system/openclaw-apps.service` (when enabled)

7. Operator UX:
- `/etc/update-motd.d/99-openclaw-status` (when enabled)
- `/home/hendaz/.zshrc` + `~/.oh-my-zsh` (when enabled)

8. Reporting helper:
- `/opt/openclaw/bin/report.sh`

## Testing

```bash
make test-scripts
make test-docker
make test-vagrant
```

## Deferred Work

- Multi-instance support on one host (future feature)
