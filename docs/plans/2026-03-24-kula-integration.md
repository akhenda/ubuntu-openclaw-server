# Kula Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Kula as a first-class monitoring app with host-metric access and a dedicated route at `monitor.akhenda.net`.

**Architecture:** Kula will be rendered as a managed app service, but with `pid: host`, `network_mode: host`, and `/proc` access for accurate metrics. Traefik routing will use a dedicated dynamic config that forwards `monitor.akhenda.net` to the host-exposed Kula port instead of the shared Docker edge network.

**Tech Stack:** Bash installer phases, shell tests, Docker Compose, Traefik dynamic config, Cloudflare Tunnel, homepage metadata.

---

### Task 1: Add Failing Tests for Kula Config and Apps Phase

**Files:**
- Modify: `tests/test_apps_phase.sh`
- Modify: `tests/test_apps_hub_phase.sh`
- Modify: `tests/test_edge_phase.sh`
- Modify: `scripts/lib/config.sh`

**Step 1: Write the failing test**

Add assertions for:
- `KULA_*` env fixture values
- Kula source/image config being exported into rendered helpers
- Kula host-metric service rendering expectations
- Kula route expectations in edge dynamic config

**Step 2: Run test to verify it fails**

Run:
- `bash tests/test_apps_phase.sh`
- `bash tests/test_apps_hub_phase.sh`
- `bash tests/test_edge_phase.sh`

Expected: FAIL because Kula config and route rendering do not exist yet.

**Step 3: Write minimal implementation**

Add `KULA_*` defaults, exports, and validation to config.

**Step 4: Run test to verify it passes**

Run the same three commands.

Expected: PASS

### Task 2: Render Kula as a First-Class Host-Metrics App

**Files:**
- Modify: `scripts/lib/apps.sh`
- Modify: `scripts/lib/verify.sh`
- Modify: `config/example.env`
- Modify: `config/.env`

**Step 1: Write the failing test**

Add test assertions for a rendered Kula service that uses:
- `network_mode: host`
- `pid: host`
- `/proc:/proc:ro`
- homepage labels for `monitor.akhenda.net`

**Step 2: Run test to verify it fails**

Run:
- `bash tests/test_apps_phase.sh`
- `bash tests/test_apps_hub_phase.sh`
- `bash tests/test_verify_phase.sh`

Expected: FAIL because the Kula service does not yet exist.

**Step 3: Write minimal implementation**

Render a dedicated Kula service using the upstream image and host-metric access settings. Add verification rules for the new artifacts and helper content.

**Step 4: Run test to verify it passes**

Run the same commands.

Expected: PASS

### Task 3: Add Dedicated Traefik Dynamic Route for Kula

**Files:**
- Modify: `scripts/lib/edge.sh`
- Modify: `tests/test_edge_phase.sh`
- Modify: `scripts/lib/verify.sh`

**Step 1: Write the failing test**

Add assertions that the edge dynamic config includes a Kula route for `monitor.akhenda.net` pointing to `host.docker.internal:<KULA_PORT>`.

**Step 2: Run test to verify it fails**

Run: `bash tests/test_edge_phase.sh`

Expected: FAIL because the route is not yet present.

**Step 3: Write minimal implementation**

Render a dedicated Kula Traefik dynamic config and include it in the edge file set.

**Step 4: Run test to verify it passes**

Run: `bash tests/test_edge_phase.sh`

Expected: PASS

### Task 4: Run Verification and Review Final Diff

**Files:**
- Modify: `scripts/lib/apps.sh`
- Modify: `scripts/lib/config.sh`
- Modify: `scripts/lib/edge.sh`
- Modify: `scripts/lib/verify.sh`
- Modify: `config/example.env`
- Modify: `tests/test_apps_phase.sh`
- Modify: `tests/test_apps_hub_phase.sh`
- Modify: `tests/test_edge_phase.sh`
- Modify: `tests/test_verify_phase.sh`

**Step 1: Run focused verification**

Run:
- `bash tests/test_apps_phase.sh`
- `bash tests/test_apps_hub_phase.sh`
- `bash tests/test_edge_phase.sh`
- `bash tests/test_verify_phase.sh`

Expected: PASS

**Step 2: Run nearby regression coverage**

Run:
- `bash tests/test_openclaw_phase.sh`
- `bash -n scripts/install.sh scripts/lib/*.sh tests/test_apps_phase.sh tests/test_apps_hub_phase.sh tests/test_edge_phase.sh tests/test_verify_phase.sh tests/test_openclaw_phase.sh`

Expected: PASS

**Step 3: Review final diff**

Run:
- `git diff -- config/example.env scripts/lib/config.sh scripts/lib/apps.sh scripts/lib/edge.sh scripts/lib/verify.sh tests/test_apps_phase.sh tests/test_apps_hub_phase.sh tests/test_edge_phase.sh tests/test_verify_phase.sh docs/plans/2026-03-24-kula-design.md docs/plans/2026-03-24-kula-integration.md`

Expected: Kula-specific changes only.
