# OpenClaw Scripts

This directory contains both **current** and **deprecated** scripts for OpenClaw installation and deployment.

---

## ⚠️ IMPORTANT: Migration to Unified Script

**The individual scripts in this directory are now DEPRECATED.**

Please use the new **unified installation script** instead:

```bash
# From the repository root
./unified-install-openclaw.sh
```

The unified script provides:
- ✅ All functionality from individual scripts
- ✅ Better security (no hardcoded credentials)
- ✅ Multi-provider support (Anthropic, OpenAI, Gemini)
- ✅ Workspace preservation
- ✅ Both local and remote installation
- ✅ Built-in diagnostics and troubleshooting

See the main [README.md](../README.md) for complete usage documentation.

---

## Current Scripts (Use These)

### unified-install-openclaw.sh (Recommended)
**Location:** `../unified-install-openclaw.sh` (repository root)

The comprehensive, all-in-one installation script that replaces all scripts below.

**Usage:**
```bash
# Interactive mode
./unified-install-openclaw.sh

# With all options
./unified-install-openclaw.sh \
  --anthropic-key "sk-ant-..." \
  --telegram-token "123:ABC..." \
  --openai-key "sk-proj-..." \
  --gemini-key "AIza..."

# Remote installation
./unified-install-openclaw.sh \
  --mode remote \
  --ssh-host root@your-server.com \
  --ssh-auth password \
  --anthropic-key "sk-ant-..."

# Run diagnostics
./unified-install-openclaw.sh --diagnose
```

---

## Deprecated Scripts (Do Not Use)

The following scripts are **deprecated** and kept only for reference. They have been integrated into the unified script:

### ~~install-openclaw.sh~~ → Use `unified-install-openclaw.sh`
**Deprecated:** Basic installation script
**Replaced by:** `unified-install-openclaw.sh` (local mode)
**Reason:** No multi-provider support, no workspace preservation

### ~~deploy-remote.sh~~ → Use `unified-install-openclaw.sh --mode remote`
**Deprecated:** Transfer files to remote server
**Replaced by:** `unified-install-openclaw.sh --mode remote`
**Reason:** Hardcoded credentials, limited functionality

### ~~run-remote.sh~~ → Use `unified-install-openclaw.sh --mode remote`
**Deprecated:** Execute installation remotely
**Replaced by:** `unified-install-openclaw.sh --mode remote`
**Reason:** Hardcoded credentials, no SSH key support

### ~~verify-remote.sh~~ → Use `unified-install-openclaw.sh --mode remote`
**Deprecated:** Pre-deployment verification
**Replaced by:** Built into unified script's remote mode
**Reason:** Hardcoded credentials, now integrated

### ~~verify-installation.sh~~ → Use `unified-install-openclaw.sh --diagnose`
**Deprecated:** Post-installation verification
**Replaced by:** `unified-install-openclaw.sh --diagnose`
**Reason:** Now integrated with more comprehensive checks

### ~~troubleshoot-telegram.sh~~ → Use `unified-install-openclaw.sh --diagnose`
**Deprecated:** Telegram diagnostics and fixes
**Replaced by:** `unified-install-openclaw.sh --diagnose`
**Reason:** Hardcoded credentials, now integrated

### ~~fix-telegram-pairing.sh~~ → Use `unified-install-openclaw.sh --diagnose`
**Deprecated:** Auto-approve Telegram pairing
**Replaced by:** Built into unified script diagnostics
**Reason:** Hardcoded user ID, better integrated flow

### ~~fix-telegram-config.sh~~ (if exists)
**Deprecated:** Enable Telegram plugin
**Replaced by:** `unified-install-openclaw.sh --telegram-token`
**Reason:** Hardcoded credentials, cleaner implementation

---

## Migration Guide

### Old Workflow → New Workflow

**Before (using individual scripts):**
```bash
# 1. Verify remote server
./scripts/verify-remote.sh

# 2. Deploy files
./scripts/deploy-remote.sh

# 3. Run installation
./scripts/run-remote.sh

# 4. Troubleshoot Telegram
./scripts/troubleshoot-telegram.sh

# 5. Fix pairing
./scripts/fix-telegram-pairing.sh
```

**After (using unified script):**
```bash
# Single command does everything
./unified-install-openclaw.sh \
  --mode remote \
  --ssh-host root@your-server.com \
  --ssh-auth password \
  --anthropic-key "sk-ant-..." \
  --telegram-token "123:ABC..."

# If issues arise, run diagnostics
./unified-install-openclaw.sh --diagnose
```

### Key Differences

| Old Scripts | Unified Script |
|------------|---------------|
| Hardcoded SSH credentials | Prompted or CLI arguments |
| Hardcoded Telegram user ID | Parameter-based |
| Multiple manual steps | Single automated flow |
| Anthropic only | Multi-provider (Anthropic, OpenAI, Gemini) |
| No workspace preservation | Optional workspace backup/restore |
| Separate diagnostic scripts | Built-in `--diagnose` mode |
| Password auth only | Password or SSH key auth |

---

## Security Improvements

The unified script addresses all security issues from the deprecated scripts:

### Removed Hardcoded Values
### New Security Features
- ✅ No hardcoded credentials anywhere
- ✅ Secure password prompting with `read -s`
- ✅ Environment variable support
- ✅ SSH key authentication option
- ✅ `chmod 600` on all credential files
- ✅ No credentials logged to files

---

## Utility Scripts (Still Useful)

These scripts remain useful for specific tasks:

### sanitize-script.sh
Scan for hardcoded secrets before committing.

```bash
./scripts/sanitize-script.sh
```

**Status:** ✅ Still useful for pre-commit checks

### fetch-logs.sh
Retrieve logs from remote server (if using old scripts).

```bash
./scripts/fetch-logs.sh
```

**Status:** ⚠️ Only needed if using deprecated remote scripts

---

## Testing

To test the unified script:

```bash
# Run automated tests
./test-unified-install.sh

# Syntax check
bash -n ./unified-install-openclaw.sh

# Help output
./unified-install-openclaw.sh --help
```

---

## Questions?

- **For unified script usage:** See [README.md](../README.md)
- **For migration help:** Run `./unified-install-openclaw.sh --help`
- **For issues:** Open an issue on the repository

---

## Archive Note

The deprecated scripts in this directory are kept for:
1. Reference purposes
2. Backwards compatibility (if needed)
3. Historical record

They will be removed in a future version once the unified script has been thoroughly tested and adopted.

**Last updated:** 2026-02-12
**Unified script version:** 2.0.0
