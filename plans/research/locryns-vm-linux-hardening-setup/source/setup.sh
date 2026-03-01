#!/usr/bin/env bash
# =============================================================================
# VM Linux Hardening & Setup Script
# Supports: Ubuntu 22.04+ / Debian 12+
# Usage:   sudo bash setup.sh <username>
#          sudo DRY_RUN=1 bash setup.sh <username>          # preview only
#          sudo BACKDOOR_PORT=59999 bash setup.sh <username> # custom backdoor port
# Example: sudo bash setup.sh laurent
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# CONSTANTS & CONFIG
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${1:-}"
SSH_PUB_KEY_FILE="${SCRIPT_DIR}/${TARGET_USER}.pub"
BACKDOOR_PORT="${BACKDOOR_PORT:-62847}"
BACKDOOR_PORT_FILE="/root/.backdoor_port"
BACKDOOR_SSHD_CONFIG="/etc/ssh/sshd_backdoor_config"
BACKDOOR_SERVICE="sshd-backdoor"
BACKDOOR_LOG="/var/log/backdoor_access.log"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_BACKUP="${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
DRY_RUN="${DRY_RUN:-0}"
LOG_FILE="/var/log/vm-setup.log"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# LOGGING
# ---------------------------------------------------------------------------
log() { echo -e "${CYAN}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
log_ok() { echo -e "${GREEN}[OK]${NC}    $*" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
log_err() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2; }
log_step() { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}" | tee -a "$LOG_FILE"; }
dry() { echo -e "${YELLOW}[DRY-RUN]${NC} Would run: $*" | tee -a "$LOG_FILE"; }

run() {
	if [[ "$DRY_RUN" == "1" ]]; then
		dry "$@"
	else
		"$@"
	fi
}

# ---------------------------------------------------------------------------
# PRE-FLIGHT CHECKS
# ---------------------------------------------------------------------------
preflight() {
	log_step "Pre-flight checks"

	# Username argument required
	if [[ -z "$TARGET_USER" ]]; then
		log_err "Usage: sudo bash setup.sh <username>"
		log_err "Example: sudo bash setup.sh laurent"
		exit 1
	fi

	# Validate username (alphanumeric + dash/underscore, 1-32 chars)
	if ! [[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
		log_err "Invalid username: '${TARGET_USER}' (lowercase letters, digits, dash, underscore only)"
		exit 1
	fi
	log_ok "Target user: ${TARGET_USER}"

	# Must be root
	if [[ $EUID -ne 0 ]]; then
		log_err "This script must be run as root: sudo bash $0 <username>"
		exit 1
	fi

	# OS detection
	if [[ -f /etc/os-release ]]; then
		# shellcheck source=/dev/null
		source /etc/os-release
		case "$ID" in
		ubuntu | debian) log_ok "Detected OS: $PRETTY_NAME" ;;
		*)
			log_err "Unsupported OS: $ID. Only Ubuntu and Debian are supported."
			exit 1
			;;
		esac
	else
		log_err "Cannot detect OS (/etc/os-release not found)."
		exit 1
	fi

	# SSH public key must exist
	if [[ ! -f "$SSH_PUB_KEY_FILE" ]]; then
		log_err "SSH public key not found: $SSH_PUB_KEY_FILE"
		log_err "Place your public key file as '${TARGET_USER}.pub' next to this script."
		exit 1
	fi
	log_ok "SSH public key found: $SSH_PUB_KEY_FILE"

	# Validate key format
	if ! ssh-keygen -l -f "$SSH_PUB_KEY_FILE" &>/dev/null; then
		log_err "Invalid SSH public key format: $SSH_PUB_KEY_FILE"
		exit 1
	fi
	log_ok "SSH public key format valid"

	# Ensure log file is writable
	touch "$LOG_FILE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# STEP 1 — SYSTEM UPDATE
# ---------------------------------------------------------------------------
step_system_update() {
	log_step "Step 1 — System update"

	run apt-get update -qq
	run apt-get upgrade -y -qq
	run apt-get install -y -qq \
		curl \
		wget \
		git \
		ufw \
		fail2ban \
		unattended-upgrades \
		apt-transport-https \
		ca-certificates \
		gnupg \
		lsb-release \
		sudo \
		rsyslog \
		auditd \
		net-tools

	# Enable unattended-upgrades for security patches
	if [[ "$DRY_RUN" != "1" ]]; then
		cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
		log_ok "Unattended-upgrades configured"
	fi

	log_ok "System updated and base packages installed"
}

# ---------------------------------------------------------------------------
# STEP 2 — USER LAURENT
# ---------------------------------------------------------------------------
step_create_user() {
	log_step "Step 2 — User '${TARGET_USER}'"

	# Idempotent: only create if not exists
	if id "$TARGET_USER" &>/dev/null; then
		log_ok "User '${TARGET_USER}' already exists — skipping creation"
	else
		run useradd \
			--create-home \
			--shell /bin/bash \
			--comment "${TARGET_USER} - admin user" \
			"$TARGET_USER"
		log_ok "User '${TARGET_USER}' created"
	fi

	# Ensure sudo group membership
	if [[ "$DRY_RUN" != "1" ]]; then
		usermod -aG sudo "$TARGET_USER"
		# Lock password (key-only auth)
		passwd -l "$TARGET_USER" &>/dev/null || true
	fi
	log_ok "User '${TARGET_USER}' added to sudo, password locked"

	# Install SSH public key (idempotent)
	local SSH_DIR="/home/${TARGET_USER}/.ssh"
	local AUTH_KEYS="${SSH_DIR}/authorized_keys"
	local PUB_KEY
	PUB_KEY="$(cat "$SSH_PUB_KEY_FILE")"

	if [[ "$DRY_RUN" != "1" ]]; then
		install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "$SSH_DIR"
		touch "$AUTH_KEYS"
		chmod 600 "$AUTH_KEYS"
		chown "$TARGET_USER":"$TARGET_USER" "$AUTH_KEYS"

		if grep -qF "$PUB_KEY" "$AUTH_KEYS" 2>/dev/null; then
			log_ok "SSH public key already in authorized_keys — skipping"
		else
			echo "$PUB_KEY" >>"$AUTH_KEYS"
			log_ok "SSH public key installed for '${TARGET_USER}'"
		fi
	fi

	# Sudoers — no password for sudo (optional, remove if unwanted)
	if [[ "$DRY_RUN" != "1" ]]; then
		local SUDOERS_FILE="/etc/sudoers.d/${TARGET_USER}"
		if [[ ! -f "$SUDOERS_FILE" ]]; then
			echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" >"$SUDOERS_FILE"
			chmod 440 "$SUDOERS_FILE"
			log_ok "Sudoers entry created for '${TARGET_USER}'"
		else
			log_ok "Sudoers entry already exists — skipping"
		fi
	fi
}

# ---------------------------------------------------------------------------
# STEP 3 — SSH INITIAL HARDENING (pre-Tailscale)
# ---------------------------------------------------------------------------
step_ssh_hardening() {
	log_step "Step 3 — SSH hardening (initial)"

	if [[ "$DRY_RUN" != "1" ]]; then
		# Backup only if not already backed up in this run
		if [[ ! -f "${SSHD_CONFIG}.bak" ]]; then
			cp "$SSHD_CONFIG" "$SSHD_BACKUP"
			# Keep a stable "original" backup
			cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"
			log_ok "sshd_config backed up to $SSHD_BACKUP"
		fi

		# Apply hardening settings using sed (idempotent — replace or append)
		apply_sshd_option() {
			local key="$1"
			local value="$2"
			if grep -qE "^#?${key}" "$SSHD_CONFIG"; then
				sed -i "s|^#\?${key}.*|${key} ${value}|" "$SSHD_CONFIG"
			else
				echo "${key} ${value}" >>"$SSHD_CONFIG"
			fi
		}

		apply_sshd_option "PasswordAuthentication" "no"
		apply_sshd_option "PubkeyAuthentication" "yes"
		apply_sshd_option "PermitRootLogin" "no"
		apply_sshd_option "MaxAuthTries" "3"
		apply_sshd_option "LoginGraceTime" "30"
		apply_sshd_option "X11Forwarding" "no"
		apply_sshd_option "AllowAgentForwarding" "no"
		apply_sshd_option "AllowTcpForwarding" "no"
		apply_sshd_option "PermitEmptyPasswords" "no"
		apply_sshd_option "ClientAliveInterval" "300"
		apply_sshd_option "ClientAliveCountMax" "2"
		apply_sshd_option "AuthorizedKeysFile" ".ssh/authorized_keys"

		# Validate config before restarting
		if ! sshd -t; then
			log_err "sshd config validation failed! Restoring backup..."
			cp "${SSHD_CONFIG}.bak" "$SSHD_CONFIG"
			exit 1
		fi

		systemctl restart sshd
		log_ok "SSH hardened and restarted"
	else
		log_ok "[DRY-RUN] Would harden sshd_config and restart sshd"
	fi
}

# ---------------------------------------------------------------------------
# STEP 4 — TAILSCALE
# ---------------------------------------------------------------------------
step_tailscale() {
	log_step "Step 4 — Tailscale"

	# Idempotent: check if already installed
	if command -v tailscale &>/dev/null; then
		log_ok "Tailscale already installed — skipping install"
	else
		log "Installing Tailscale..."
		run curl -fsSL https://tailscale.com/install.sh | sh
		log_ok "Tailscale installed"
	fi

	# Enable and start tailscaled
	if [[ "$DRY_RUN" != "1" ]]; then
		systemctl enable --now tailscaled 2>/dev/null || true
	fi

	# Check if already connected
	if tailscale status &>/dev/null 2>&1; then
		log_ok "Tailscale already connected"
		# Idempotent: ensure --ssh mode is enabled
		if [[ "$DRY_RUN" != "1" ]]; then
			tailscale set --ssh 2>/dev/null && log_ok "Tailscale SSH mode enabled" || log_warn "Could not enable Tailscale SSH mode (run: sudo tailscale set --ssh)"
		fi
	else
		echo ""
		echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
		echo -e "${BOLD}  ACTION REQUIRED: Tailscale authentication${NC}"
		echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
		echo -e "  Run the following command to authenticate:"
		echo -e "  ${BOLD}tailscale up --ssh${NC}"
		echo -e ""
		echo -e "  Visit the URL shown, then press ENTER here to continue."
		echo -e "  (SSH will then be restricted to Tailscale only — via 'tailscale ssh')"
		echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
		echo ""

		if [[ "$DRY_RUN" != "1" ]]; then
			tailscale up --ssh || true
			# Wait for connectivity
			local max_wait=60
			local waited=0
			while ! tailscale status &>/dev/null 2>&1; do
				sleep 2
				waited=$((waited + 2))
				if [[ $waited -ge $max_wait ]]; then
					log_err "Tailscale did not connect within ${max_wait}s. Run 'tailscale up' manually."
					log_err "Then re-run this script to continue."
					exit 1
				fi
			done
			log_ok "Tailscale connected"
		fi
	fi
}

# ---------------------------------------------------------------------------
# STEP 5 — UFW LOCKDOWN
# ---------------------------------------------------------------------------
step_ufw() {
	log_step "Step 5 — UFW firewall lockdown"

	if [[ "$DRY_RUN" == "1" ]]; then
		log "Would configure UFW: deny all, allow tailscale0, limit backdoor port ${BACKDOOR_PORT}"
		return
	fi

	# Get Tailscale IP for reference
	local TAILSCALE_IP
	TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || echo 'NOT_CONNECTED')"
	if [[ "$TAILSCALE_IP" == "NOT_CONNECTED" ]]; then
		log_err "Cannot get Tailscale IP — is Tailscale connected?"
		exit 1
	fi
	log_ok "Tailscale IP: ${TAILSCALE_IP}"

	# Reset UFW to clean state (idempotent — always safe to reset before configuring)
	ufw --force reset

	# Default policies
	ufw default deny incoming
	ufw default allow outgoing
	ufw default deny forward

	# Allow only necessary ports on tailscale0 (principle of least privilege)
	ufw allow in on tailscale0 to any port 22 proto tcp comment "SSH via Tailscale"
	# OpenClaw gateway port (tailscale0 only) — also set in step_openclaw_gateway
	ufw allow in on tailscale0 to any port "${OPENCLAW_GATEWAY_PORT:-3000}" proto tcp comment "openclaw-gateway"

	# Emergency backdoor: publicly accessible (fallback if Tailscale is down) + rate-limited
	ufw limit "${BACKDOOR_PORT}/tcp" comment "Emergency backdoor - audited"

	# Enable UFW
	ufw --force enable

	log_ok "UFW enabled: deny all | tailscale0: SSH:22, gateway:${OPENCLAW_GATEWAY_PORT:-3000} | public: backdoor:${BACKDOOR_PORT} (rate-limited)"
	log_warn "Public SSH port 22 is now BLOCKED — use Tailscale (${TAILSCALE_IP}) to SSH"

	# Store backdoor port for reference
	echo "$BACKDOOR_PORT" >"$BACKDOOR_PORT_FILE"
	chmod 600 "$BACKDOOR_PORT_FILE"
	log_ok "Backdoor port stored in $BACKDOOR_PORT_FILE"
}

# ---------------------------------------------------------------------------
# STEP 6 — SSH BIND TO TAILSCALE ONLY
# ---------------------------------------------------------------------------
step_ssh_bind_tailscale() {
	log_step "Step 6 — Bind SSH to Tailscale interface only"

	local TAILSCALE_IP
	TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || echo '')"

	if [[ -z "$TAILSCALE_IP" ]]; then
		log_err "Cannot get Tailscale IP — skipping SSH bind"
		return 1
	fi

	echo ""
	echo -e "${BOLD}${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${BOLD}  WARNING: SSH will be restricted to Tailscale ONLY${NC}"
	echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "  After this step, SSH is accessible ONLY via: ${BOLD}${TAILSCALE_IP}${NC}"
	echo -e "  Make sure your Tailscale client is connected before continuing!"
	echo -e "  Emergency backdoor port: ${BOLD}${BACKDOOR_PORT}${NC} (configured in next step)"
	echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""
	read -rp "Type 'yes' to confirm and continue: " CONFIRM

	if [[ "$CONFIRM" != "yes" ]]; then
		log_warn "SSH binding to Tailscale cancelled by user. Skipping."
		return 0
	fi

	if [[ "$DRY_RUN" != "1" ]]; then
		# Add ListenAddress directive (idempotent)
		if grep -q "^ListenAddress ${TAILSCALE_IP}" "$SSHD_CONFIG"; then
			log_ok "SSH ListenAddress already set to ${TAILSCALE_IP} — skipping"
		else
			# Remove any existing ListenAddress lines first
			sed -i '/^ListenAddress/d' "$SSHD_CONFIG"
			# Add the Tailscale-only listen address
			echo "ListenAddress ${TAILSCALE_IP}" >>"$SSHD_CONFIG"
			log_ok "SSH ListenAddress set to ${TAILSCALE_IP}"
		fi

		# Restrict AllowUsers
		if grep -q "^AllowUsers" "$SSHD_CONFIG"; then
			log_ok "AllowUsers already configured — skipping"
		else
			echo "AllowUsers ${TARGET_USER}" >>"$SSHD_CONFIG"
		fi

		# Validate and restart
		if ! sshd -t; then
			log_err "sshd config validation failed! Restoring backup..."
			cp "${SSHD_CONFIG}.bak" "$SSHD_CONFIG"
			exit 1
		fi

		systemctl restart sshd
		log_ok "SSH restarted — now listening on Tailscale IP ${TAILSCALE_IP} only"
	fi
}

# ---------------------------------------------------------------------------
# STEP 7 — OPENCLAW
# ---------------------------------------------------------------------------
step_openclaw() {
	log_step "Step 7 — OpenClaw AI agent"

	# Idempotent check
	if command -v openclaw &>/dev/null; then
		log_ok "OpenClaw already installed ($(openclaw --version 2>/dev/null || echo 'version unknown')) — skipping"
		return 0
	fi

	if [[ "$DRY_RUN" == "1" ]]; then
		log "Would install OpenClaw via official install script"
		return 0
	fi

	log "Installing OpenClaw..."

	# Primary: official installer
	if curl -fsSL https://openclaw.ai/install.sh -o /tmp/openclaw-install.sh; then
		bash /tmp/openclaw-install.sh && rm -f /tmp/openclaw-install.sh
		log_ok "OpenClaw installed via official installer"
	else
		log_warn "Official OpenClaw installer failed — trying npm fallback"

		# Ensure Node.js is available (install if needed)
		if ! command -v node &>/dev/null; then
			log "Installing Node.js (LTS) via NodeSource..."
			curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
			apt-get install -y nodejs
		fi

		# npm global install as fallback
		if command -v npm &>/dev/null; then
			npm install -g openclaw
			log_ok "OpenClaw installed via npm"
		else
			log_err "Could not install OpenClaw — npm not available after Node.js install"
			log_warn "Install manually: https://openclaw.ai"
		fi
	fi

	# Verify installation
	if command -v openclaw &>/dev/null; then
		log_ok "OpenClaw verified: $(openclaw --version 2>/dev/null || echo 'installed')"
	else
		log_warn "OpenClaw binary not in PATH — may require re-login (PATH reload)"
	fi
}

# ---------------------------------------------------------------------------
# STEP 8 — EMERGENCY BACKDOOR
# ---------------------------------------------------------------------------
step_backdoor() {
	log_step "Step 8 — Emergency backdoor (hidden, audited)"

	if [[ "$DRY_RUN" == "1" ]]; then
		log "Would configure emergency backdoor on port ${BACKDOOR_PORT}"
		return 0
	fi

	# Separate sshd config for backdoor (minimal attack surface)
	# ListenAddress 0.0.0.0 intentional: public fallback if Tailscale is down
	if [[ ! -f "$BACKDOOR_SSHD_CONFIG" ]]; then
		cat >"$BACKDOOR_SSHD_CONFIG" <<EOF
# Emergency Backdoor SSHD Configuration
# Port: ${BACKDOOR_PORT}
# This file is intentionally separate from the main sshd_config
# Listens on all interfaces — fallback access when Tailscale is unavailable
# Access is logged to ${BACKDOOR_LOG}

Port ${BACKDOOR_PORT}
ListenAddress 0.0.0.0
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin no
MaxAuthTries 2
LoginGraceTime 20
AllowUsers ${TARGET_USER}
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitEmptyPasswords no
ClientAliveInterval 120
ClientAliveCountMax 1
LogLevel VERBOSE
SyslogFacility AUTH
PidFile /run/sshd-backdoor.pid
EOF
		log_ok "Backdoor SSHD config created: $BACKDOOR_SSHD_CONFIG"
	else
		log_ok "Backdoor SSHD config already exists — skipping"
	fi

	# Audit log
	touch "$BACKDOOR_LOG"
	chmod 640 "$BACKDOOR_LOG"
	log_ok "Backdoor audit log: $BACKDOOR_LOG"

	# rsyslog rule to capture backdoor logins
	local RSYSLOG_RULE="/etc/rsyslog.d/99-backdoor-audit.conf"
	if [[ ! -f "$RSYSLOG_RULE" ]]; then
		cat >"$RSYSLOG_RULE" <<EOF
# Redirect AUTH logs from sshd-backdoor to dedicated log
:programname, isequal, "sshd" -${BACKDOOR_LOG}
& stop
EOF
		systemctl restart rsyslog 2>/dev/null || true
		log_ok "rsyslog audit rule created"
	fi

	# Systemd service for backdoor sshd
	local SERVICE_FILE="/etc/systemd/system/${BACKDOOR_SERVICE}.service"
	if [[ ! -f "$SERVICE_FILE" ]]; then
		cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Emergency Backdoor SSH (audited)
After=network.target sshd.service
ConditionPathExists=${BACKDOOR_SSHD_CONFIG}

[Service]
Type=notify
ExecStartPre=/usr/sbin/sshd -t -f ${BACKDOOR_SSHD_CONFIG}
ExecStart=/usr/sbin/sshd -D -f ${BACKDOOR_SSHD_CONFIG}
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=42s

[Install]
WantedBy=multi-user.target
EOF
		systemctl daemon-reload
		systemctl enable --now "$BACKDOOR_SERVICE"
		log_ok "Backdoor systemd service enabled and started"
	else
		# Idempotent: ensure it's running
		systemctl enable "$BACKDOOR_SERVICE" 2>/dev/null || true
		systemctl start "$BACKDOOR_SERVICE" 2>/dev/null || true
		log_ok "Backdoor service already configured — ensured running"
	fi

	# auditd rule: track backdoor config access
	if command -v auditctl &>/dev/null; then
		auditctl -w "$BACKDOOR_SSHD_CONFIG" -p rwxa -k backdoor_config 2>/dev/null || true
		auditctl -w "$BACKDOOR_LOG" -p rwa -k backdoor_access 2>/dev/null || true
		log_ok "auditd rules added for backdoor file monitoring"
	fi

	log_warn "BACKDOOR DETAILS — KEEP SECRET:"
	log_warn "  Port:       ${BACKDOOR_PORT}"
	log_warn "  User:       ${TARGET_USER}"
	log_warn "  Auth:       SSH key only (no password)"
	log_warn "  Logs:       ${BACKDOOR_LOG}"
	log_warn "  UFW:        rate-limited, publicly accessible (fallback if Tailscale is down)"
	log_warn "  Access:     ssh -p ${BACKDOOR_PORT} ${TARGET_USER}@<PUBLIC_IP>"
}

# ---------------------------------------------------------------------------
# STEP 8b — OPENCODE
# ---------------------------------------------------------------------------
step_opencode() {
	log_step "Step 8b — OpenCode"

	# Idempotent check
	if command -v opencode &>/dev/null; then
		log_ok "OpenCode already installed — skipping"
		return 0
	fi

	if [[ "$DRY_RUN" == "1" ]]; then
		log "Would install OpenCode via official install script"
		return 0
	fi

	log "Installing OpenCode..."

	# Official installer
	if curl -fsSL https://opencode.ai/install | sh; then
		log_ok "OpenCode installed"
	else
		log_warn "OpenCode install failed — trying npm fallback"
		if command -v npm &>/dev/null; then
			npm install -g opencode-ai
			log_ok "OpenCode installed via npm"
		else
			log_err "Could not install OpenCode — see https://opencode.ai"
		fi
	fi

	if command -v opencode &>/dev/null; then
		log_ok "OpenCode verified: $(opencode --version 2>/dev/null || echo 'installed')"
	else
		log_warn "OpenCode binary not in PATH — may require re-login"
	fi
}

# ---------------------------------------------------------------------------
# STEP 8c — CLAUDE CODE (claude-code CLI)
# ---------------------------------------------------------------------------
step_claude_code() {
	log_step "Step 8c — Claude Code"

	# Idempotent check
	if command -v claude &>/dev/null; then
		log_ok "Claude Code already installed — skipping"
		return 0
	fi

	if [[ "$DRY_RUN" == "1" ]]; then
		log "Would install Claude Code via npm"
		return 0
	fi

	# Ensure Node.js is available
	if ! command -v node &>/dev/null; then
		log "Installing Node.js (LTS) via NodeSource..."
		curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
		apt-get install -y -qq nodejs
		log_ok "Node.js installed"
	fi

	log "Installing Claude Code..."
	if npm install -g @anthropic-ai/claude-code; then
		log_ok "Claude Code installed"
	else
		log_err "Could not install Claude Code — see https://docs.anthropic.com/en/docs/claude-code"
	fi

	if command -v claude &>/dev/null; then
		log_ok "Claude Code verified: $(claude --version 2>/dev/null || echo 'installed')"
	else
		log_warn "claude binary not in PATH — may require re-login"
	fi
}

# ---------------------------------------------------------------------------
# STEP 9 — OPENCLAW GATEWAY (Tailscale-only)
# ---------------------------------------------------------------------------
step_openclaw_gateway() {
	log_step "Step 9 — OpenClaw Gateway (Tailscale-only)"

	local TAILSCALE_IP
	TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || echo '')"

	if [[ -z "$TAILSCALE_IP" ]]; then
		log_warn "Tailscale not connected — skipping OpenClaw Gateway config"
		return 0
	fi

	# OpenClaw config directory (runs as TARGET_USER)
	local OPENCLAW_CONFIG_DIR="/home/${TARGET_USER}/.config/openclaw"
	local OPENCLAW_CONFIG="${OPENCLAW_CONFIG_DIR}/config.json5"
	local OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-3000}"

	if [[ "$DRY_RUN" == "1" ]]; then
		log "Would configure OpenClaw Gateway on ${TAILSCALE_IP}:${OPENCLAW_GATEWAY_PORT}"
		return 0
	fi

	# Create config directory
	install -d -m 750 -o "$TARGET_USER" -g "$TARGET_USER" "$OPENCLAW_CONFIG_DIR"

	# Idempotent: only create if not exists
	if [[ -f "$OPENCLAW_CONFIG" ]]; then
		log_ok "OpenClaw config already exists — skipping (edit manually if needed: ${OPENCLAW_CONFIG})"
	else
		# Generate a strong random token
		local GATEWAY_TOKEN
		GATEWAY_TOKEN="$(openssl rand -hex 32)"

		cat >"$OPENCLAW_CONFIG" <<EOF
// OpenClaw configuration — generated by vm-setup script
// Gateway bound to Tailscale IP only (not exposed to public internet)
// Edit this file to configure channels (WhatsApp, Telegram, etc.)
{
  gateway: {
    mode: "network",
    bind: "${TAILSCALE_IP}",
    port: ${OPENCLAW_GATEWAY_PORT},
    auth: {
      mode: "token",
      token: "${GATEWAY_TOKEN}",
    },
  },
  session: {
    dmScope: "per-channel-peer",
  },
  tools: {
    profile: "messaging",
    exec: { security: "deny", ask: "always" },
    elevated: { enabled: false },
    fs: { workspaceOnly: true },
  },
}
EOF
		chown "$TARGET_USER":"$TARGET_USER" "$OPENCLAW_CONFIG"
		chmod 600 "$OPENCLAW_CONFIG"
		log_ok "OpenClaw config written: ${OPENCLAW_CONFIG}"
		log_ok "Gateway token generated (stored in config — keep secret!)"
	fi

	# UFW rule for gateway port is already set in step_ufw (tailscale0 only)
	log_ok "UFW: port ${OPENCLAW_GATEWAY_PORT} restricted to tailscale0 (set in step_ufw)"

	# Systemd service for openclaw gateway (runs as TARGET_USER)
	local OC_SERVICE="openclaw-gateway"
	local OC_SERVICE_FILE="/etc/systemd/system/${OC_SERVICE}.service"

	if [[ ! -f "$OC_SERVICE_FILE" ]]; then
		# Find openclaw binary path
		local OC_BIN
		OC_BIN="$(su - "$TARGET_USER" -c 'command -v openclaw 2>/dev/null || echo ""')"
		if [[ -z "$OC_BIN" ]]; then
			# Try common install paths
			for p in /usr/local/bin/openclaw /usr/bin/openclaw "$HOME/.local/bin/openclaw"; do
				[[ -x "$p" ]] && OC_BIN="$p" && break
			done
		fi

		if [[ -z "$OC_BIN" ]]; then
			log_warn "Cannot find openclaw binary — skipping systemd service (install OpenClaw first, then re-run)"
			return 0
		fi

		cat >"$OC_SERVICE_FILE" <<EOF
[Unit]
Description=OpenClaw AI Gateway (Tailscale-only)
After=network-online.target tailscaled.service
Wants=network-online.target
Requires=tailscaled.service

[Service]
Type=simple
User=${TARGET_USER}
Group=${TARGET_USER}
ExecStart=${OC_BIN} gateway start
Restart=on-failure
RestartSec=10s
Environment=HOME=/home/${TARGET_USER}
WorkingDirectory=/home/${TARGET_USER}

# Security hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/${TARGET_USER}/.config/openclaw

[Install]
WantedBy=multi-user.target
EOF
		systemctl daemon-reload
		systemctl enable --now "$OC_SERVICE"
		log_ok "OpenClaw gateway systemd service enabled and started"
	else
		systemctl enable "$OC_SERVICE" 2>/dev/null || true
		systemctl restart "$OC_SERVICE" 2>/dev/null || true
		log_ok "OpenClaw gateway service already configured — restarted"
	fi

	log_ok "OpenClaw Gateway accessible at: http://${TAILSCALE_IP}:${OPENCLAW_GATEWAY_PORT}"
	log_warn "Gateway token is in: ${OPENCLAW_CONFIG} (mode 600, ${TARGET_USER} only)"
}

# ---------------------------------------------------------------------------
# STEP 10 — FAIL2BAN TUNING
# ---------------------------------------------------------------------------
step_fail2ban() {
	log_step "Step 10 — fail2ban"

	if [[ "$DRY_RUN" == "1" ]]; then
		log "Would configure fail2ban for sshd and backdoor"
		return 0
	fi

	local F2B_LOCAL="/etc/fail2ban/jail.local"
	if [[ ! -f "$F2B_LOCAL" ]]; then
		cat >"$F2B_LOCAL" <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 3
banaction = ufw

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3

[sshd-backdoor]
enabled  = true
port     = ${BACKDOOR_PORT}
filter   = sshd
logpath  = ${BACKDOOR_LOG}
maxretry = 2
bantime  = 24h
EOF
		systemctl enable --now fail2ban
		log_ok "fail2ban configured and started"
	else
		systemctl enable --now fail2ban 2>/dev/null || true
		log_ok "fail2ban jail.local already exists — ensuring running"
	fi
}

# ---------------------------------------------------------------------------
# STEP 10 — SUMMARY
# ---------------------------------------------------------------------------
step_summary() {
	local TAILSCALE_IP
	TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || echo 'NOT_CONNECTED')"

	echo ""
	echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${BOLD}${GREEN}  ✅  VM HARDENING COMPLETE${NC}"
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""
	echo -e "  ${BOLD}User:${NC}              ${TARGET_USER} (sudo, SSH key only)"
	echo -e "  ${BOLD}SSH via Tailscale:${NC} tailscale ssh ${TARGET_USER}@${TAILSCALE_IP}"
	echo -e "  ${BOLD}SSH (backup):${NC}      ssh -p ${BACKDOOR_PORT} ${TARGET_USER}@<PUBLIC_IP>"
	echo -e "  ${BOLD}Tailscale IP:${NC} ${TAILSCALE_IP}"
	echo -e "  ${BOLD}UFW:${NC}          deny all | allow tailscale0 | limit :${BACKDOOR_PORT}"
	local OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-3000}"
	echo -e "  ${BOLD}OpenClaw:${NC}         $(command -v openclaw &>/dev/null && echo 'installed' || echo 'installed (reload PATH)')"
	echo -e "  ${BOLD}OpenCode:${NC}         $(command -v opencode &>/dev/null && echo 'installed' || echo 'installed (reload PATH)')"
	echo -e "  ${BOLD}Claude Code:${NC}      $(command -v claude &>/dev/null && echo 'installed' || echo 'installed (reload PATH)')"
	echo -e "  ${BOLD}OpenClaw Gateway:${NC} http://${TAILSCALE_IP}:${OPENCLAW_GATEWAY_PORT} (Tailscale-only)"
	echo -e "  ${BOLD}Gateway config:${NC}   /home/${TARGET_USER}/.config/openclaw/config.json5"
	echo -e "  ${BOLD}Audit log:${NC}        ${BACKDOOR_LOG}"
	echo -e "  ${BOLD}Setup log:${NC}        ${LOG_FILE}"
	echo ""
	echo -e "  ${BOLD}${YELLOW}⚠  NEXT STEPS:${NC}"
	echo -e "  1. Test SSH via Tailscale:  ${BOLD}tailscale ssh ${TARGET_USER}@${TAILSCALE_IP}${NC}"
	echo -e "  2. Test backdoor works:     ${BOLD}ssh -p ${BACKDOOR_PORT} ${TARGET_USER}@<PUBLIC_IP>${NC}"
	echo -e "  3. Access OpenClaw Gateway: ${BOLD}http://${TAILSCALE_IP}:${OPENCLAW_GATEWAY_PORT}${NC}"
	echo -e "  4. Run OpenClaw onboard:    ${BOLD}openclaw onboard${NC}"
	echo -e "  5. Check gateway service:   ${BOLD}sudo systemctl status openclaw-gateway${NC}"
	echo -e "  6. Keep ${BACKDOOR_PORT_FILE} secret"
	echo -e "  7. Check fail2ban status:   ${BOLD}sudo fail2ban-client status${NC}"
	echo ""
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""

	log_ok "Setup complete. Log: $LOG_FILE"
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
main() {
	echo ""
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${BOLD}  VM Linux Hardening & Setup Script — user: ${TARGET_USER}${NC}"
	echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	if [[ "$DRY_RUN" == "1" ]]; then
		echo -e "  ${YELLOW}MODE: DRY RUN — no changes will be made${NC}"
	fi
	echo ""

	preflight
	step_system_update
	step_create_user
	step_ssh_hardening
	step_tailscale
	step_ufw
	step_ssh_bind_tailscale
	step_openclaw
	step_opencode
	step_claude_code
	step_openclaw_gateway
	step_backdoor
	step_fail2ban
	step_summary
}

main "$@"
