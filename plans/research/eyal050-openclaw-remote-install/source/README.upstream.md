# OpenClaw Automated Installation

A comprehensive installation framework for automating OpenClaw setup on Ubuntu 24.04/22.04, supporting both local and remote deployment with multiple AI providers.

## What is OpenClaw?

OpenClaw is an open-source personal AI assistant that runs locally on your machine. It provides a persistent, customizable AI companion accessible through popular chat applications like Telegram, WhatsApp, Slack, Discord, and more.

## Features

The unified installation script (v2.0.0) provides:

- **One-command installation** - Single script to set up everything
- **Multiple execution modes** - Local or remote installation
- **Multi-provider support** - Anthropic (Claude), OpenAI (GPT), Google Gemini
- **Telegram integration** - Connect your AI assistant to Telegram
- **Workspace preservation** - Keep agent memory across reinstalls
- **Auto-installation of prerequisites** - Docker, Git, UFW firewall
- **Remote dashboard access** - Control panel accessible from any device
- **SSH authentication** - Password or SSH key-based remote deployment
- **Automated diagnostics** - Built-in troubleshooting and health checks
- **Comprehensive logging** - Detailed logs for troubleshooting
- **Security hardening** - No hardcoded credentials, secure variable handling

## Prerequisites

### Required
- Fresh Ubuntu 24.04 VPS (or Ubuntu 22.04)
- Root or sudo access
- Anthropic API key (get from [console.anthropic.com](https://console.anthropic.com))
- At least 2GB RAM and 10GB disk space

### Optional
- OpenAI API key (for GPT models)
- Google Gemini API key
- Telegram bot token (get from [@BotFather](https://t.me/BotFather) on Telegram)
- For remote installation: SSH access to target server

## Quick Start

### 1. Get Your API Keys

**Anthropic API Key:**
1. Go to [console.anthropic.com](https://console.anthropic.com)
2. Create an account or sign in
3. Navigate to API Keys section
4. Create a new API key
5. Copy the key (starts with `sk-ant-`)

**Telegram Bot Token:**
1. Open Telegram and search for [@BotFather](https://t.me/BotFather)
2. Send `/newbot` command
3. Follow the prompts to create your bot
4. Copy the bot token (format: `123456789:ABC...`)

### 2. Download and Run the Unified Installation Script

#### Option A: Interactive Mode (Recommended for Beginners)

```bash
# Clone this repository
git clone https://github.com/YOUR_USERNAME/oclaw.git
cd oclaw

# Run the installation script interactively
./unified-install-openclaw.sh
```

The script will prompt you for all required information.

#### Option B: Command-Line Mode (Recommended for Automation)

```bash
# Clone this repository
git clone https://github.com/YOUR_USERNAME/oclaw.git
cd oclaw

# Run with all parameters specified
./unified-install-openclaw.sh \
  --anthropic-key "sk-ant-..." \
  --telegram-token "123:ABC..." \
  --openai-key "sk-proj-..." \
  --gemini-key "AIza..."
```

#### Option C: Environment Variables (Legacy Compatibility)

```bash
# Set your API keys as environment variables
export ANTHROPIC_API_KEY="sk-ant-..."
export TELEGRAM_BOT_TOKEN="123456789:ABC..."

# Run the installation script
./unified-install-openclaw.sh
```

### 3. Access the Dashboard

After installation completes, you'll see output with:
- Dashboard URL: `http://YOUR_SERVER_IP:18789`
- Gateway token for authentication

Open your browser and navigate to the dashboard URL. Enter the gateway token when prompted.

### 4. Connect to Telegram

#### Automated Pairing (Recommended)

**During installation:**
```bash
./unified-install-openclaw.sh \
  --telegram-token "123:ABC..." \
  --telegram-auto-pairing yes
```

The installer will prompt you to send a message to your bot, then automatically approve the pairing.

**After installation:**
```bash
# Run the pairing helper script
./scripts/telegram-pairing-helper.sh
```

The script will auto-detect pending pairing requests and approve them.

#### Manual Pairing

1. Send a message to your bot on Telegram (e.g., "Hello")
2. Bot responds with a pairing code
3. Approve the pairing:
   - **Option A**: Run `./scripts/telegram-pairing-helper.sh`
   - **Option B**: Approve in the dashboard at `http://YOUR_SERVER_IP:18789`
4. Send another message to verify it works

For detailed pairing instructions and troubleshooting, see [TELEGRAM-PAIRING.md](./TELEGRAM-PAIRING.md).

## Advanced Usage

### Remote Installation

Install OpenClaw on a remote server via SSH:

#### With Password Authentication

```bash
./unified-install-openclaw.sh \
  --mode remote \
  --ssh-host root@your-server.com \
  --ssh-auth password \
  --ssh-password "your-password" \
  --anthropic-key "sk-ant-..."
```

#### Full Example with Telegram and Workspace Preservation

```bash
./unified-install-openclaw.sh \
  --mode remote \
  --ssh-host root@123.456.789.000 \
  --ssh-auth password \
  --ssh-password MyCoolPasswordForMyLinuxVM \
  --anthropic-key 'sk-ant-oat01-skdjfhsdjkfhsdkjfh.....' \
  --telegram-token '1234567890:abcdefg.....' \
  --preserve-workspace
```

#### With SSH Key Authentication

```bash
./unified-install-openclaw.sh \
  --mode remote \
  --ssh-host root@your-server.com \
  --ssh-auth key \
  --ssh-key ~/.ssh/id_rsa \
  --anthropic-key "sk-ant-..."
```

### Workspace Preservation

Preserve agent memory and conversation history across reinstalls:

```bash
./unified-install-openclaw.sh \
  --preserve-workspace \
  --anthropic-key "sk-ant-..."
```

When reinstalling, the script will:
1. Back up your existing workspace to `~/.openclaw-backups/`
2. Perform a clean installation
3. Restore your workspace after installation
4. Keep the last 5 backups automatically

### Multi-Provider Configuration

Configure multiple AI providers simultaneously:

```bash
./unified-install-openclaw.sh \
  --anthropic-key "sk-ant-..." \
  --openai-key "sk-proj-..." \
  --gemini-key "AIza..." \
  --telegram-token "123:ABC..."
```

This will configure:
- Anthropic (Claude Sonnet 4.5) as primary
- OpenAI (GPT-4) as alternative
- Google Gemini as alternative
- Telegram channel integration

### Diagnostic Mode

Run diagnostics on an existing installation:

```bash
./unified-install-openclaw.sh --diagnose
```

This checks:
- Docker container status
- Gateway accessibility
- Configuration file validity
- Telegram plugin status
- Workspace permissions

### Configuration Options

You can customize the installation with these flags:

```bash
--install-dir <path>      # Installation directory (default: ~/openclaw)
--config-dir <path>       # Configuration directory (default: ~/.openclaw)
--gateway-port <port>     # Gateway port (default: 18789)
--preserve-workspace      # Preserve workspace across reinstalls
```

All configuration options can also be set as environment variables. See `./unified-install-openclaw.sh --help` for complete documentation.

## Managing OpenClaw

### Common Commands

```bash
# Start services
cd ~/openclaw/openclaw && docker compose up -d

# Stop services
cd ~/openclaw/openclaw && docker compose down

# Restart gateway
cd ~/openclaw/openclaw && docker compose restart openclaw-gateway

# View logs
cd ~/openclaw/openclaw && docker compose logs -f openclaw-gateway

# Check status
cd ~/openclaw/openclaw && docker compose ps
```

### Configuration Files

- **Main config:** `~/.openclaw/openclaw.json`
- **Auth profiles:** `~/.openclaw/agents/main/agent/auth-profiles.json`
- **Environment:** `~/openclaw/openclaw/.env`
- **Workspace:** `~/.openclaw/workspace`

## Troubleshooting

### Dashboard not accessible

1. Check container status:
   ```bash
   cd ~/openclaw/openclaw && docker compose ps
   ```

2. Check gateway logs:
   ```bash
   cd ~/openclaw/openclaw && docker compose logs openclaw-gateway
   ```

3. Verify firewall:
   ```bash
   sudo ufw status
   ```

4. Check port binding:
   ```bash
   sudo netstat -tlnp | grep 18789
   ```

### Telegram bot not responding

1. Verify bot token in configuration:
   ```bash
   cat ~/.openclaw/openclaw.json | grep -A 3 telegram
   ```

2. Check gateway logs for Telegram errors:
   ```bash
   cd ~/openclaw/openclaw && docker compose logs openclaw-gateway | grep -i telegram
   ```

3. Ensure pairing request was approved in dashboard

### Installation failed

Check the installation log for detailed error messages:
```bash
cat ~/openclaw-install-logs/install-*.log
```

Common issues:
- **Insufficient disk space:** Ensure at least 10GB available
- **Docker permission errors:** Log out and back in after installation
- **Port already in use:** Change `OPENCLAW_GATEWAY_PORT` to different port

## Security Considerations

The default installation uses HTTP with `allowInsecureAuth: true` for simplicity. This is acceptable for personal use, but for production:

1. **Use HTTPS** - Set up a reverse proxy (Caddy/Nginx) with SSL certificate
2. **VPN Access** - Access the dashboard through a VPN
3. **IP Restrictions** - Limit firewall rules to specific IP addresses:
   ```bash
   export UFW_ALLOW_FROM="YOUR_IP_ADDRESS/32"
   ```

## Uninstalling

To completely remove OpenClaw:

```bash
# Stop and remove containers
cd ~/openclaw/openclaw && docker compose down -v

# Remove installation directory
rm -rf ~/openclaw

# Remove configuration directory
rm -rf ~/.openclaw

# Remove firewall rule (optional)
sudo ufw delete allow 18789/tcp
```

## Migration from Legacy Scripts

If you were using the old `install-openclaw.sh` script, the unified script is a drop-in replacement with additional features:

**Old way:**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export TELEGRAM_BOT_TOKEN="123:ABC..."
./install-openclaw.sh
```

**New way (same result):**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export TELEGRAM_BOT_TOKEN="123:ABC..."
./unified-install-openclaw.sh
```

The unified script is fully backward compatible with environment variables. See `scripts/README.md` for information about deprecated scripts.

## Resources

- [OpenClaw Official Documentation](https://docs.openclaw.ai/)
- [OpenClaw GitHub Repository](https://github.com/openclaw/openclaw)
- [Telegram Integration Guide](https://docs.openclaw.ai/channels/telegram)
- [Anthropic API Documentation](https://docs.anthropic.com/)

## License

MIT License - See OpenClaw repository for details

## Support

For issues with this installation script, please open an issue on this repository.

For OpenClaw-specific questions, visit the [official documentation](https://docs.openclaw.ai/) or [GitHub repository](https://github.com/openclaw/openclaw).
