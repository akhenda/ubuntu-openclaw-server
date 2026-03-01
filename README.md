# infra-ubuntu-2404-openclaw

Bash-first, idempotent Ubuntu 24.04 server setup toolkit for OpenClaw edge hosting.

This repository configures a server to the architecture in [docs/ARCHITECTURE_DECISION.md](docs/ARCHITECTURE_DECISION.md):

1. Secure host baseline (`hendaz` admin + `openclaw` runtime, SSH on `1773`, firewall baseline)
2. Cloudflare Tunnel + Traefik edge foundation on `openclaw-edge`
3. OpenClaw runtime + mandatory workspace policy injection
4. Global apps registry and deploy helpers
5. Deployment reporting helper with channel fallback
6. Post-install verification checks

## Current State

The active automation entrypoint is:

- `scripts/install.sh`

The installer is modular and runs phases in this order:

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

## Prerequisites

Controller machine:

1. Python 3.11+ (recommended)
2. `venv`
3. Optional tooling dependencies (split profiles):
   - `requirements-test.txt` (Molecule stack)
   - `requirements-lint.txt` (YAML lint)
   - `requirements-dev.txt` (full local profile; includes test + lint)
4. Docker (for `molecule/docker`)
5. Vagrant + provider (VirtualBox/libvirt) (for `molecule/vagrant`)

Target machine:

1. Ubuntu Server 24.04 LTS
2. Access with sudo-capable user for first run

## Quickstart

```bash
python -m venv .venv && source .venv/bin/activate
make deps
make deps-test
cp config/example.env config/.env
$EDITOR config/.env
make check-config
make test-scripts
make test-docker
make test-vagrant
make run-install
```

## Make Targets (Bash Toolkit)

- `make deps`: alias of `make deps-dev`
- `make deps-dev`: install full local profile (`requirements-dev.txt`)
- `make deps-test`: install Molecule profile (`requirements-test.txt`)
- `make deps-lint`: install lint profile (`requirements-lint.txt`)
- `make lint`: run Bash syntax checks and YAML lint
- `make check-config`: validate `config/.env` and print effective config
- `make run-install`: execute full installer
- `make test-scripts`: run Bash phase tests
- `make test-docker`: run Molecule docker scenario (installer dry-run)
- `make test-vagrant`: run Molecule vagrant scenario (installer live baseline)

You can override the config path:

```bash
make check-config CONFIG_FILE=/path/to/file.env
make run-install CONFIG_FILE=/path/to/file.env
```

## Configuration

Copy `config/example.env` to `config/.env` and set your real values.

Core required contract:

1. `DOMAIN`
2. `APPS_DOMAIN`
3. `BOT_NAME`
4. `TUNNEL_UUID`
5. `CF_ZONE_ID`
6. `CF_API_TOKEN`
7. `TAILSCALE_AUTHKEY` (mandatory)
8. `OPENCLAW_GATEWAY_TOKEN`
9. `OPENCLAW_GATEWAY_PASSWORD`
10. `ADMIN_SSH_PUBLIC_KEY` or `ADMIN_SSH_PUBLIC_KEY_FILE`

Hub contract defaults:

1. `HUB_ENABLE=true`
2. `HUB_AUTOCREATE_ON_FIRST_APP=true`
3. `HUB_PRIMARY_HOST=hub.<APPS_DOMAIN>`
4. `HUB_ALIAS_HOST=apps.<DOMAIN>` (optional alias)
5. Hub app cards must link to each app’s real subdomain (`https://<app>.<APPS_DOMAIN>`).

Key locked defaults:

1. `ADMIN_USER=hendaz`
2. `RUNTIME_USER=openclaw`
3. `SSH_PORT=1773`
4. `EDGE_NETWORK_NAME=openclaw-edge`
5. `OPENCLAW_POLICY_INJECTION=true`

Reporting owner is configurable:

- `REPORT_OWNER_NAME` (default `Joseph`)

## What Gets Generated

Installer-managed artifacts (default paths):

1. Edge stack:
- `/opt/openclaw/edge/traefik/traefik.yml`
- `/opt/openclaw/edge/cloudflared/config.yml`
- `/opt/openclaw/edge/docker-compose.yml`
2. DNS helpers:
- `/opt/openclaw/bin/cf_dns_ensure_wildcard.sh`
- `/opt/openclaw/bin/cf_dns_upsert_subdomain.sh`
3. OpenClaw runtime:
- `/opt/openclaw/openclaw/config/openclaw.json`
- `/opt/openclaw/openclaw/.env`
- `/opt/openclaw/openclaw/docker-compose.yml`
- `/opt/openclaw/openclaw/workspace/policies/deploy/AGENTS.md`
- `/etc/systemd/system/openclaw-gateway.service` (when enabled)
4. Apps helpers:
- `/opt/openclaw/apps/docker-compose.yml`
- `/opt/openclaw/bin/register_app.py`
- `/opt/openclaw/bin/deploy_app.sh`
5. Reporting helper:
- `/opt/openclaw/bin/report.sh`

## OpenClaw Notes

The toolkit configures OpenClaw to run behind Traefik and injects deployment policy context via `bootstrap-extra-files`.

After first successful install, typical manual next steps are:

1. Bring up/confirm channels and auth in OpenClaw.
2. Use `openclaw-cli` for dashboard/device/provider setup as needed.
3. Use generated helpers for app lifecycle and reporting.

## Testing

Script-level tests:

```bash
make test-scripts
```

These tests are deterministic dry-run checks of each phase contract.

The authoritative implementation path remains the Bash toolkit under `scripts/` + `config/example.env`.

## Deferred Work

- Multi-instance support on one host (planned future feature)
