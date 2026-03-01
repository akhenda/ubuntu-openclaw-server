# Telegram Pairing Guide

This guide explains how to pair your Telegram account with OpenClaw and troubleshoot common pairing issues.

---

## Table of Contents

1. [How Pairing Works](#how-pairing-works)
2. [Automated Pairing (Recommended)](#automated-pairing-recommended)
3. [Manual Pairing](#manual-pairing)
4. [Troubleshooting](#troubleshooting)
5. [Security Considerations](#security-considerations)
6. [Advanced Usage](#advanced-usage)

---

## How Pairing Works

OpenClaw uses a secure pairing system to connect your Telegram account:

1. **User sends message** → Telegram bot receives message from unknown user
2. **Pairing request created** → Bot generates unique pairing code (e.g., `3HW3XQLL`)
3. **User receives code** → Bot responds with pairing code and approval instructions
4. **Admin approves** → Pairing request moved from "pending" to "approved" list
5. **User authenticated** → User can now interact with the bot

### Why Pairing?

- **Security**: Prevents unauthorized access to your AI assistant
- **Access Control**: You decide who can use your bot
- **Audit Trail**: Track which Telegram users are approved
- **Multi-User**: Support multiple authorized users with different permissions

---

## Automated Pairing (Recommended)

### During Installation

Use the unified installation script with auto-pairing enabled:

```bash
./unified-install-openclaw.sh \
  --anthropic-key "sk-ant-..." \
  --telegram-token "123456:ABC-DEF..." \
  --telegram-auto-pairing yes
```

**What happens:**
1. Installation completes
2. Script prompts you to send a message to the bot
3. You send a message (e.g., "Hello")
4. Script auto-detects the pairing request
5. Script auto-approves the pairing
6. You can immediately use the bot

**Interactive mode** (default):
```bash
./unified-install-openclaw.sh \
  --anthropic-key "sk-ant-..." \
  --telegram-token "123456:ABC-DEF..." \
  --telegram-auto-pairing prompt
```

This will ask you during installation whether you want to pair now.

### After Installation

Use the standalone pairing helper script:

```bash
# Navigate to OpenClaw directory
cd ~/openclaw

# Run pairing helper
./scripts/telegram-pairing-helper.sh
```

**Interactive mode workflow:**
1. Script detects pending pairing requests
2. Shows user ID and pairing code
3. Asks for confirmation
4. Approves pairing
5. Restarts gateway
6. Done!

**Direct mode** (if you know the user ID and code):
```bash
./scripts/telegram-pairing-helper.sh \
  --user-id 789273209 \
  --code 3HW3XQLL
```

**Remote mode** (for remote servers):
```bash
./scripts/telegram-pairing-helper.sh \
  --ssh-host root@your-server.com \
  --ssh-auth password
```

---

## Manual Pairing

If you prefer manual approval or the automated method doesn't work:

### Method 1: Dashboard (Easiest)

1. Send a message to your bot on Telegram
2. Bot responds with:
   ```
   OpenClaw: access not configured.
   Your Telegram user id: 789273209
   Pairing code: 3HW3XQLL
   Ask the bot owner to approve...
   ```
3. Open dashboard: `http://your-server-ip:18789`
4. Log in with your gateway token
5. Navigate to Telegram settings
6. Approve the pending pairing request
7. Send another message to verify

### Method 2: Edit JSON File (Advanced)

**Location:** `/root/.openclaw/credentials/telegram-pairing.json`

**Before approval:**
```json
{
  "version": 1,
  "requests": [
    {
      "id": "789273209",
      "code": "3HW3XQLL",
      "createdAt": "2026-02-17T12:41:39.644Z",
      "lastSeenAt": "2026-02-17T12:51:03.990Z",
      "meta": {
        "firstName": "Eyal",
        "accountId": "default"
      }
    }
  ]
}
```

**After approval** (move request to approved array):
```json
{
  "version": 1,
  "requests": [],
  "approved": [
    {
      "id": "789273209",
      "code": "3HW3XQLL",
      "createdAt": "2026-02-17T12:41:39.644Z",
      "approvedAt": "2026-02-17T13:00:00.000Z",
      "lastSeenAt": "2026-02-17T12:51:03.990Z",
      "meta": {
        "firstName": "Eyal",
        "accountId": "default"
      }
    }
  ]
}
```

**Steps:**
```bash
# 1. Backup current file
sudo cp /root/.openclaw/credentials/telegram-pairing.json \
     /root/.openclaw/credentials/telegram-pairing.json.backup

# 2. Edit file (use nano, vim, or your preferred editor)
sudo nano /root/.openclaw/credentials/telegram-pairing.json

# 3. Move request from "requests" to "approved" array
# 4. Add "approvedAt" field with current timestamp
# 5. Save file

# 6. Fix permissions
sudo chown 1000:1000 /root/.openclaw/credentials/telegram-pairing.json
sudo chmod 600 /root/.openclaw/credentials/telegram-pairing.json

# 7. Restart gateway
cd ~/openclaw/openclaw
docker compose restart openclaw-gateway

# 8. Wait 5 seconds for gateway to start
sleep 5

# 9. Test by sending message to bot
```

---

## Troubleshooting

### Bot Not Responding After Pairing

**Symptom:** Pairing appears approved, but bot still doesn't respond.

**Solution:**
1. Verify pairing file has correct format:
   ```bash
   cat /root/.openclaw/credentials/telegram-pairing.json | jq '.'
   ```
2. Check that user is in `approved` array, not `requests`
3. Restart gateway:
   ```bash
   cd ~/openclaw/openclaw && docker compose restart openclaw-gateway
   ```
4. Check gateway logs:
   ```bash
   cd ~/openclaw/openclaw && docker compose logs -f openclaw-gateway
   ```

### Pairing Code Not Generated

**Symptom:** Send message to bot, but no pairing code appears.

**Possible causes:**
1. **Wrong bot token**: Verify `TELEGRAM_BOT_TOKEN` is correct
2. **Bot not connected**: Check gateway logs for Telegram plugin errors
3. **Firewall issues**: Ensure outbound HTTPS (443) is allowed

**Verification:**
```bash
# Check if bot token is valid
curl -s "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getMe" | jq '.'

# Should return:
# {
#   "ok": true,
#   "result": {
#     "id": 123456,
#     "is_bot": true,
#     "username": "your_bot_name"
#   }
# }

# Check gateway logs
cd ~/openclaw/openclaw
docker compose logs openclaw-gateway | grep -i telegram
```

### Permission Denied Errors

**Symptom:** Cannot edit pairing file or restart containers.

**Solution:**
```bash
# Fix file ownership (pairing file must be owned by uid 1000)
sudo chown 1000:1000 /root/.openclaw/credentials/telegram-pairing.json
sudo chmod 600 /root/.openclaw/credentials/telegram-pairing.json

# If docker command fails, add sudo
sudo docker compose restart openclaw-gateway
```

### Script Can't Find Pairing Request

**Symptom:** `telegram-pairing-helper.sh` says "No pending requests found"

**Solution:**
1. Send a message to the bot FIRST, then run script
2. Check if request is already approved:
   ```bash
   cat /root/.openclaw/credentials/telegram-pairing.json | jq '.approved'
   ```
3. If approved, user should be able to use bot already
4. If not approved, manually approve using Method 2 above

### Gateway Won't Restart

**Symptom:** `docker compose restart` fails or hangs.

**Solution:**
```bash
# Force restart with down/up
cd ~/openclaw/openclaw
docker compose down
docker compose up -d

# If still fails, check Docker daemon
sudo systemctl status docker
sudo systemctl restart docker
```

---

## Security Considerations

### Best Practices

✅ **DO:**
- Keep pairing file permissions at `600` (read/write owner only)
- Set file ownership to `1000:1000` (node user in container)
- Create backups before modifying pairing file
- Use auto-pairing only on trusted networks
- Regularly review approved users list
- Remove users who no longer need access

❌ **DON'T:**
- Share pairing codes publicly
- Commit pairing file to git (already in `.gitignore`)
- Set world-readable permissions on pairing file
- Approve unknown user IDs without verification
- Use `--telegram-auto-pairing yes` in public/untrusted environments

### File Security

**Pairing file location:** `/root/.openclaw/credentials/telegram-pairing.json`

**Required permissions:**
```bash
# Ownership: uid 1000 (node user), gid 1000
# Permissions: 600 (rw-------)

ls -l /root/.openclaw/credentials/telegram-pairing.json
# Should show:
# -rw------- 1 1000 1000 456 Feb 17 12:00 telegram-pairing.json
```

**Volume mount:** The pairing file is mounted into the Docker container at runtime. Changes on the host are immediately visible to the container after gateway restart.

### Multi-User Access

Each approved user has:
- **Unique Telegram ID**: Cannot be spoofed
- **Pairing code**: One-time use for initial pairing
- **Metadata**: First name, account ID for auditing

**Revoking access:**
```bash
# 1. Edit pairing file
sudo nano /root/.openclaw/credentials/telegram-pairing.json

# 2. Remove user from "approved" array
# 3. Save file

# 4. Restart gateway
cd ~/openclaw/openclaw && docker compose restart openclaw-gateway
```

---

## Advanced Usage

### Batch Approve Multiple Users

```bash
# Create list of user IDs to approve
cat > users.txt <<EOF
789273209 3HW3XQLL
123456789 ABCD1234
987654321 XYZA9876
EOF

# Approve each user
while read -r user_id code; do
  ./scripts/telegram-pairing-helper.sh --user-id "$user_id" --code "$code"
done < users.txt
```

### Automated Pairing in CI/CD

```bash
# In deployment script
./unified-install-openclaw.sh \
  --mode remote \
  --ssh-host root@production-server \
  --ssh-auth key \
  --telegram-token "$TELEGRAM_BOT_TOKEN" \
  --telegram-auto-pairing no  # Disable auto-pairing in automated deployments

# Pairing done manually post-deployment for security
```

### Remote Pairing via SSH

```bash
# Approve pairing on remote server without logging in
./scripts/telegram-pairing-helper.sh \
  --ssh-host root@your-server.com \
  --ssh-auth password \
  --user-id 789273209 \
  --code 3HW3XQLL
```

### Monitoring Pairing Activity

```bash
# View all approved users
jq '.approved[]' /root/.openclaw/credentials/telegram-pairing.json

# View pending requests
jq '.requests[]' /root/.openclaw/credentials/telegram-pairing.json

# Count approved users
jq '.approved | length' /root/.openclaw/credentials/telegram-pairing.json

# Find user by ID
jq '.approved[] | select(.id == "789273209")' /root/.openclaw/credentials/telegram-pairing.json
```

---

## Related Documentation

- [README.md](./README.md) - Main installation guide
- [unified-install-openclaw.sh](./unified-install-openclaw.sh) - Installation script with `--help`
- [scripts/telegram-pairing-helper.sh](./scripts/telegram-pairing-helper.sh) - Pairing automation script

---

## Support

If you encounter issues not covered in this guide:

1. Check gateway logs: `docker compose logs -f openclaw-gateway`
2. Verify Telegram token: `curl https://api.telegram.org/bot<TOKEN>/getMe`
3. Review pairing file: `cat /root/.openclaw/credentials/telegram-pairing.json | jq '.'`
4. Try manual approval via dashboard
5. Open an issue on GitHub with logs and error messages

---

**Last Updated:** 2026-02-17
**Version:** 1.0.0
