# Telegram Bot Workspace Path Fix

## Problem Description

The Telegram bot was not responding to messages, with the following error appearing in logs:

```
Error: EACCES: permission denied, mkdir '/root/.openclaw/workspace'
```

## Root Cause

The `openclaw.json` configuration file was setting the workspace path to the **host system path** instead of the **Docker container path**:

- ❌ **Incorrect** (host path): `/root/.openclaw/workspace`
- ✅ **Correct** (container path): `/home/node/.openclaw/workspace`

### Why This Happened

The installation script was using the `${OPENCLAW_WORKSPACE_DIR}` variable, which contains the host path where the workspace directory is created. However, the configuration file is read **inside the Docker container**, where the workspace is mounted at a different path (`/home/node/.openclaw/workspace`).

## Solution

### 1. For New Installations

The fix is now built into the installation script (`unified-install-openclaw.sh`):

- The workspace path in `openclaw.json` is now hardcoded to the correct container path
- A diagnostic check validates the workspace path is correct
- A comment explains why the container path is used

### 2. For Existing Installations

Run the automated fix script:

```bash
./scripts/fix-workspace-path.sh
```

This script will:
1. Check the current workspace path in your configuration
2. Fix it if incorrect
3. Restart the gateway
4. Verify the fix worked

**For remote servers:**
```bash
SSH_PASSWORD='your-password' REMOTE_HOST='user@server' ./scripts/fix-workspace-path.sh
```

### 3. Manual Fix (if needed)

If you prefer to fix it manually:

1. Edit the configuration file:
   ```bash
   nano /root/.openclaw/openclaw.json
   ```

2. Find the workspace path in the `agents.defaults` section:
   ```json
   "agents": {
     "defaults": {
       "workspace": "/root/.openclaw/workspace",  # <- WRONG
       ...
     }
   }
   ```

3. Change it to the container path:
   ```json
   "agents": {
     "defaults": {
       "workspace": "/home/node/.openclaw/workspace",  # <- CORRECT
       ...
     }
   }
   ```

4. Restart the gateway:
   ```bash
   cd ~/openclaw/openclaw
   docker compose restart openclaw-gateway
   ```

## Verification

After applying the fix, verify it worked:

1. Check the configuration:
   ```bash
   cat /root/.openclaw/openclaw.json | grep -A 3 '"agents"'
   ```

   Should show: `"workspace": "/home/node/.openclaw/workspace"`

2. Check gateway logs for errors:
   ```bash
   cd ~/openclaw/openclaw
   docker compose logs openclaw-gateway --tail=50 | grep -i "error\|workspace"
   ```

   Should show no permission errors.

3. Test the bot:
   - Send a message to your Telegram bot
   - It should respond successfully

## Prevention

The fix has been committed to the repository:
- **Commit**: 13fa9f9 - "Fix workspace path configuration issue causing bot permission errors"
- **Branch**: feature/telegram-e2e-verification
- **PR**: #5

All future installations will have the correct configuration automatically.

## Additional Diagnostics

Run the enhanced diagnostics to check for this and other issues:

```bash
./unified-install-openclaw.sh --diagnose
```

This will run 9 comprehensive checks including workspace path validation.

## Troubleshooting

If the bot still doesn't respond after the fix:

1. Run the full troubleshooting script:
   ```bash
   ./scripts/troubleshoot-telegram.sh
   ```

2. Check if pairing is needed:
   - Send a message to the bot
   - Check for pairing requests at: http://your-server:18789
   - Or run: `./scripts/fix-telegram-pairing.sh`

3. Verify all services are running:
   ```bash
   cd ~/openclaw/openclaw
   docker compose ps
   ```

## Files Changed

1. `unified-install-openclaw.sh`
   - Fixed workspace path in config template (line 937)
   - Added comment explaining container vs host path
   - Enhanced diagnostic check 4 to validate workspace path

2. `scripts/fix-workspace-path.sh` (NEW)
   - Automated script to fix existing installations
   - Works with local and remote servers

3. `scripts/troubleshoot-telegram.sh`
   - Added detection for workspace permission errors
   - Updated manual fix suggestions

## Technical Details

### Docker Volume Mounts

The `docker-compose.yml` file mounts the workspace like this:

```yaml
volumes:
  - ${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
```

This means:
- **Outside container** (host): `/root/.openclaw/workspace`
- **Inside container**: `/home/node/.openclaw/workspace`

The OpenClaw application runs **inside the container**, so it needs to use the container path in its configuration.

### Why The Error Occurred

When the bot tried to create the workspace directory, it read the path from `openclaw.json`:
1. Config said: `/root/.openclaw/workspace`
2. Bot tried: `mkdir /root/.openclaw/workspace`
3. But `/root` doesn't exist in the container (the user is `node`, not `root`)
4. Result: `EACCES: permission denied`

With the fix:
1. Config says: `/home/node/.openclaw/workspace`
2. Bot tries: `mkdir /home/node/.openclaw/workspace`
3. Directory already exists (mounted by Docker)
4. Result: ✅ Success!
