# ClawPort Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add ClawPort as a first-class managed app with dedicated config, source sync, compose rendering, and `ui.akhenda.net` routing.

**Architecture:** Extend the existing Mission Control pattern instead of using the generic app publisher. ClawPort will be synced into `/opt/openclaw/apps`, rendered directly into the global apps compose, and routed through Traefik on an explicit host.

**Tech Stack:** Bash installer phases, shell tests, Docker Compose, Traefik labels, ruamel-based compose mutation.

---

### Task 1: Cover Config Contract

**Files:**
- Modify: `tests/test_apps_phase.sh`
- Modify: `scripts/lib/config.sh`
- Modify: `config/.env`

**Step 1: Write the failing test**

Add assertions that the apps phase dry-run references ClawPort config and source sync.

**Step 2: Run test to verify it fails**

Run: `bash tests/test_apps_phase.sh`

Expected: FAIL because ClawPort settings are not yet present in the env fixture or rendered output.

**Step 3: Write minimal implementation**

Add `CLAWPORT_*` defaults, exports, validation, and example config values.

**Step 4: Run test to verify it passes**

Run: `bash tests/test_apps_phase.sh`

Expected: PASS

### Task 2: Cover Apps Rendering

**Files:**
- Modify: `tests/test_apps_hub_phase.sh`
- Modify: `scripts/lib/apps.sh`

**Step 1: Write the failing test**

Add assertions for ClawPort source sync, explicit host routing, homepage labels, and compose service rendering.

**Step 2: Run test to verify it fails**

Run: `bash tests/test_apps_hub_phase.sh`

Expected: FAIL because ClawPort rendering does not yet exist.

**Step 3: Write minimal implementation**

Render ClawPort as a dedicated service in `ensure_hub.sh` generation and add a source sync helper similar to Mission Control.

**Step 4: Run test to verify it passes**

Run: `bash tests/test_apps_hub_phase.sh`

Expected: PASS

### Task 3: Verify End-to-End Shell Coverage

**Files:**
- Modify: `tests/test_apps_phase.sh`
- Modify: `tests/test_apps_hub_phase.sh`
- Modify: `scripts/lib/apps.sh`
- Modify: `scripts/lib/config.sh`
- Modify: `config/.env`

**Step 1: Run focused verification**

Run:
- `bash tests/test_apps_phase.sh`
- `bash tests/test_apps_hub_phase.sh`

Expected: PASS

**Step 2: Run broader regression coverage**

Run:
- `bash tests/test_openclaw_phase.sh`

Expected: PASS

**Step 3: Review diff**

Run: `git diff -- docs/plans config/.env scripts/lib/config.sh scripts/lib/apps.sh tests/test_apps_phase.sh tests/test_apps_hub_phase.sh`

Expected: ClawPort-specific additions only.
