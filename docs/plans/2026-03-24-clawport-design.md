# ClawPort First-Class Integration Design

## Goal
Integrate `JohnRiceML/clawport-ui` into the Ubuntu OpenClaw server toolkit as a first-class managed app, following the same lifecycle and routing model used for Mission Control.

## Decision
ClawPort will be managed through the apps phase instead of the generic workspace app publisher flow.

This mirrors Mission Control:
- source synced into `/opt/openclaw/apps`
- dedicated `CLAWPORT_*` config contract
- explicit compose rendering in the global apps compose
- explicit Traefik host routing for `ui.akhenda.net`
- Hub card metadata generated automatically

## Why This Approach
ClawPort is a named platform UI, not a one-off generated app. It deserves the same operator ergonomics as Mission Control:
- stable source checkout path
- deterministic compose rendering
- dedicated subdomain
- managed startup with the apps stack

This also avoids overloading the generic `<app>.<APPS_DOMAIN>` helper path, since the requested public host is `ui.akhenda.net` while the internal service name can remain `clawport-ui`.

## Configuration Contract
Add a `CLAWPORT_*` block beside the existing Mission Control settings:
- `CLAWPORT_ENABLE`
- `CLAWPORT_SERVICE_NAME`
- `CLAWPORT_HOST`
- `CLAWPORT_SOURCE_REPO`
- `CLAWPORT_SOURCE_REF`
- `CLAWPORT_SOURCE_DIR`
- `CLAWPORT_PORT`
- `CLAWPORT_OPENCLAW_BIN`
- `CLAWPORT_WORKSPACE_PATH`

Defaults should align with the existing OpenClaw installation on the host.

## Runtime Shape
The rendered service should:
- build from the synced ClawPort source tree
- attach to `openclaw-edge`
- expose only an internal app port for Traefik
- mount the OpenClaw workspace path read/write
- pass the existing OpenClaw gateway settings and workspace path as environment
- publish a Hub card pointing to `https://ui.akhenda.net`

## Constraints
- No direct public `ports:` publishing
- No edge stack changes for this app
- No second OpenClaw runtime
- Hostname must be explicitly configurable rather than derived from service name

## Verification
Add test coverage for:
- config defaults and validation
- apps phase dry-run output
- rendered apps helper script contents
- hub compose rendering metadata for ClawPort
