# Research Folder Convention

Canonical synthesis output from these research artifacts lives in:
`docs/ARCHITECTURE_DECISION.md`

Each external reference goes in its own folder:

- `plans/research/<source-name>/analysis.md`
- `plans/research/<source-name>/source/...`

Example:
- `plans/research/rarecloud-openclaw-setup/analysis.md`
- `plans/research/rarecloud-openclaw-setup/source/setup.sh`
- `plans/research/rarecloud-openclaw-setup/source/README.upstream.md`

## Why

1. Preserve exact upstream artifacts for later verification.
2. Keep analysis and source side-by-side.
3. Enable fast cross-comparison as we design the final all-in-one toolkit.

## Suggested Naming

Use lowercase kebab-case folder names combining vendor/project, e.g.:
- `rarecloud-openclaw-setup`
- `foo-secure-vps-script`

## For Every New Source

1. Save original script/docs in `source/`.
2. Write `analysis.md` with:
- what it does
- strengths
- risks
- keep/modify/reject mapping
- direct mapping to `plans/APPROVED_BASE_PLAN.md`
