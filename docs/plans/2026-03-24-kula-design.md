# Kula First-Class Integration Design

## Goal
Integrate `c0m4r/kula` as a first-class monitoring app with a dedicated public hostname at `monitor.akhenda.net`, while preserving accurate host-level Linux metrics.

## Decision
Kula will be managed as a first-class app, but it will not follow the exact same container networking shape as Mission Control or ClawPort.

Kula needs direct host visibility for metrics collection. To preserve metric accuracy, it should run with host-level access:
- `pid: host`
- `network_mode: host`
- `/proc:/proc:ro`

Because `network_mode: host` prevents normal attachment to the shared Traefik Docker network, routing should be handled through a dedicated Traefik dynamic config that points `monitor.akhenda.net` at `http://host.docker.internal:<kula-port>`.

## Why This Approach
This keeps Kula inside the managed contract of the repo:
- dedicated `KULA_*` config block
- explicit source-of-truth service rendering
- managed startup inside the apps lifecycle
- Hub entry and verification coverage

At the same time, it respects the upstream runtime expectations for accurate host metrics instead of forcing Kula into a normal app container pattern that would distort system/network visibility.

## Configuration Contract
Add a `KULA_*` block with:
- `KULA_ENABLE`
- `KULA_SERVICE_NAME`
- `KULA_HOST`
- `KULA_IMAGE`
- `KULA_PORT`

This should be enough for the first iteration. Since access control is handled by Cloudflare Zero Trust, no app-level auth config is required initially.

## Runtime Shape
The rendered Kula service should:
- use the upstream image directly
- expose its listening port only on the host loopback or host network
- mount `/proc:/proc:ro`
- run with `pid: host`
- run with `network_mode: host`
- include homepage labels so it appears in the hub

## Routing Shape
Kula cannot be routed by Traefik through Docker labels alone if it uses host networking.

Instead:
- add a dedicated Traefik dynamic config file for Kula in the edge stack
- route `monitor.akhenda.net` to `http://host.docker.internal:<kula-port>`
- keep Cloudflare Tunnel and Zero Trust in front of the hostname

This mirrors the existing pattern already used for the OpenClaw gateway dynamic route, which also targets the host rather than a normal edge-network container.

## Constraints
- Kula should remain public at the app layer because Cloudflare Zero Trust is the intended protection boundary
- no direct public Docker `ports:` exposure through app containers
- preserve existing apps stack conventions where possible, but prioritize correct host metrics over strict symmetry with Mission Control/ClawPort

## Verification
Add coverage for:
- `KULA_*` config defaults and validation
- apps phase dry-run output
- rendered apps service with host metric access
- rendered edge dynamic route for `monitor.akhenda.net`
- verification phase checks for Kula artifacts
