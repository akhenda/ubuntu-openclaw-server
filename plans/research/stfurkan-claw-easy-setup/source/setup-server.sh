#!/bin/bash
# OpenClaw Easy Server Setup (Unified)
# This script provisions a fresh VPS, automatically detects the safest authentication 
# method (SSH Keys vs Password), hardens the server, and installs OpenClaw.
# WARNING: MUST be run as root or with sudo

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script as root (e.g., sudo ./setup-server.sh)"
  exit 1
fi

# Validate OS compatibility — this script depends on apt, ufw, and Debian paths
if [ ! -f /etc/debian_version ]; then
  echo "❌ This script is designed specifically for Debian/Ubuntu systems."
  exit 1
fi

# Default Variables
NEW_USER="openclaw"
NEW_SSH_PORT="2222"

# Parse optional command line flags
# Example: bash setup-server.sh -u myadmin -p 8888
while getopts u:p: flag; do
    case "${flag}" in
        u) NEW_USER=${OPTARG};;
        p) NEW_SSH_PORT=${OPTARG};;
        *) echo "Usage: $0 [-u username] [-p ssh_port]"; exit 1;;
    esac
done

# Validate username conforms to Linux naming rules (lowercase, starts with letter/underscore)
if [[ ! "$NEW_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "❌ ERROR: Invalid username '$NEW_USER'. Must be lowercase, start with a letter or underscore, and max 32 chars."
    exit 1
fi

# Validate that the SSH port is a valid number in the TCP range
if ! [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_SSH_PORT" -lt 1 ] || [ "$NEW_SSH_PORT" -gt 65535 ]; then
    echo "❌ ERROR: Invalid port number '$NEW_SSH_PORT'. Must be a number between 1 and 65535."
    exit 1
fi

# Validate custom SSH port to prevent conflicts with reserved/active ports
# (FTP, Telnet, DNS, HTTP, HTTPS, MySQL, OpenClaw UI)
RESTRICTED_PORTS=("21" "23" "53" "80" "443" "3306" "18789")
for port in "${RESTRICTED_PORTS[@]}"; do
    if [ "$NEW_SSH_PORT" == "$port" ]; then
        echo "❌ ERROR: Port $NEW_SSH_PORT is strictly reserved or already in use."
        echo "Please choose a different SSH port (e.g., 2222, 8888, 54321)."
        exit 1
    fi
done

if [ "$NEW_SSH_PORT" == "22" ]; then
    echo "⚠️  WARNING: You have chosen to keep SSH on Port 22."
    echo "This port receives heavy automated bot traffic. Fail2Ban will protect you,"
    echo "but choosing a random port (like 2222 or 54321) is strongly recommended."
    sleep 2
fi

# Detect the server's public IP using local tools only (no external APIs)
SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || hostname -I | awk '{print $1}')

echo "================================================="
echo "   OpenClaw Automated Server Setup & Hardening   "
echo "================================================="

# --- Collect user password BEFORE enabling log redirection ---
# The tee-based log redirection (below) buffers stdout and breaks interactive
# prompts. We collect the password up-front while the terminal is still clean.
if ! id "$NEW_USER" &>/dev/null; then
    echo "================================================="
    echo "PLEASE CREATE A STRONG PASSWORD FOR THE '$NEW_USER' ACCOUNT:"
    echo "This is required to run admin commands inside your server later."
    echo "================================================="
    read -rs -p "Password: " USER_PASS
    echo
    read -rs -p "Confirm Password: " USER_PASS_CONFIRM
    echo
    if [ -z "$USER_PASS" ]; then
        echo "❌ ERROR: Password cannot be empty."
        exit 1
    fi
    if [ "$USER_PASS" != "$USER_PASS_CONFIRM" ]; then
        echo "❌ ERROR: Passwords do not match."
        exit 1
    fi
    echo ""
fi

echo "[1/8] Updating server packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -q
# --force-confdef/confold prevents dpkg from pausing on modified config file prompts
apt-get upgrade -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
apt-get autoremove -y -q

echo "[2/8] Checking for active Swapfile (Memory Protection)..."
if [ "$(swapon --show | wc -l)" -eq 0 ]; then
    echo "No swap space detected. Creating a 2GB swapfile..."
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "Swapfile created and activated successfully."
else
    echo "Swap space already exists. Skipping."
fi

echo "[3/8] Installing necessary dependencies..."
apt-get install -y -q curl wget git unzip sudo ufw fail2ban unattended-upgrades systemd-timesyncd

# Detect the correct SSH service name (Ubuntu uses 'ssh', others use 'sshd')
if systemctl list-unit-files ssh.service &>/dev/null && systemctl list-unit-files ssh.service | grep -q ssh.service; then
    SSH_SERVICE="ssh"
else
    SSH_SERVICE="sshd"
fi

echo "[4/8] Creating non-root user ($NEW_USER)..."
if id "$NEW_USER" &>/dev/null; then
    echo "User $NEW_USER already exists. Skipping creation."
else
    # Create user non-interactively, then set the password via chpasswd
    adduser --disabled-password --gecos "" "$NEW_USER"
    # Here-string keeps the password out of /proc/*/cmdline (unlike echo ... | chpasswd)
    chpasswd <<< "$NEW_USER:$USER_PASS"
    # Clear password from memory immediately
    unset USER_PASS USER_PASS_CONFIRM
    usermod -aG sudo "$NEW_USER"
    
    # Check if this server instance was provisioned with SSH keys
    if [ -f /root/.ssh/authorized_keys ] && [ -s /root/.ssh/authorized_keys ]; then
        echo "Root SSH keys detected! Copying to $NEW_USER for passwordless login..."
        mkdir -p "/home/$NEW_USER/.ssh"
        cp /root/.ssh/authorized_keys "/home/$NEW_USER/.ssh/"
        chown -R "$NEW_USER":"$NEW_USER" "/home/$NEW_USER/.ssh"
        chmod 700 "/home/$NEW_USER/.ssh"
        chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
        echo "Root SSH keys successfully copied."
    fi
fi

# --- IMPORTANT: Configure SSH BEFORE enabling the firewall ---
# Enabling UFW first would block port 22 while SSH hasn't yet moved to the new port,
# creating a lockout window if the script crashes between steps.

echo "[5/8] Hardening SSH (Custom Port & Root Disabling)..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Track whether SSH keys exist — but ALWAYS leave password auth enabled for safety.
# The user will be guided to disable it manually after verifying key login works.
SSH_KEYS_DETECTED=false
if [ -s "/home/$NEW_USER/.ssh/authorized_keys" ]; then
    SSH_KEYS_DETECTED=true
    echo "  -> SSH keys detected for $NEW_USER. Password auth will remain ON for safety."
    echo "     You will be given a command to disable it after verifying key login."
else
    echo "  -> No SSH Keys found for $NEW_USER. Password Authentication ENABLED."
fi

# Use a drop-in config file instead of sed-ing the main sshd_config.
# Cloud images (e.g., Ubuntu on DigitalOcean/AWS) ship overrides in sshd_config.d/
# like 50-cloud-init.conf that silently undo sed edits. A 00-prefixed drop-in
# file takes priority and guarantees our settings are applied.
mkdir -p /etc/ssh/sshd_config.d
cat <<EOF > /etc/ssh/sshd_config.d/00-openclaw-security.conf
# OpenClaw Security Hardening — managed by setup-server.sh
Port $NEW_SSH_PORT
PermitRootLogin no
PasswordAuthentication yes
PermitEmptyPasswords no
DebianBanner no

# Restrict login to our dedicated user only
AllowUsers $NEW_USER

# Limit brute-force window
LoginGraceTime 30
MaxAuthTries 3

# Strong cipher and MAC suites only
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com
EOF

# CRITICAL: Validate config syntax BEFORE restarting to prevent lockout
if sshd -t; then
    echo "  -> SSH configuration syntax validated successfully."
    systemctl restart "$SSH_SERVICE"
else
    echo "❌ CRITICAL: SSH configuration syntax error detected!"
    echo "   Removing the drop-in file to prevent lockout..."
    rm -f /etc/ssh/sshd_config.d/00-openclaw-security.conf
    echo "   SSH config reverted. Please check your settings and re-run the script."
    exit 1
fi

echo "[6/8] Configuring the UFW Firewall & Fail2Ban..."
ufw default deny incoming
ufw default allow outgoing
ufw limit "$NEW_SSH_PORT/tcp"

# Enable UFW (now safe — SSH is already listening on the new port)
echo "y" | ufw enable

# Configure Fail2Ban to monitor our NEW SSH PORT instead of default 22
cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = $NEW_SSH_PORT
logpath = %(sshd_log)s
backend = auto
maxretry = 5
findtime = 10m
bantime = 24h
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo "[7/8] Configuring Automatic Security Updates & NTP Time..."
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl enable systemd-timesyncd
systemctl start systemd-timesyncd

echo "[8/8] Installing & Setting Up OpenClaw as $NEW_USER..."
# Temporarily grant passwordless sudo so the OpenClaw installer can install
# its own dependencies (e.g., Node.js) without a terminal password prompt.
# This is immediately revoked after the installer finishes.
echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-openclaw-temp
chmod 440 /etc/sudoers.d/99-openclaw-temp

# Pre-create npm global bin dir and add to PATH so the OpenClaw installer
# doesn't warn about a missing PATH entry during installation.
NPM_GLOBAL_BIN="/home/$NEW_USER/.npm-global/bin"
mkdir -p "$NPM_GLOBAL_BIN"
chown -R "$NEW_USER":"$NEW_USER" "/home/$NEW_USER/.npm-global"

# Persist the PATH for future login sessions
SHELL_RC="/home/$NEW_USER/.bashrc"
if ! grep -q "$NPM_GLOBAL_BIN" "$SHELL_RC" 2>/dev/null; then
    echo "export PATH=\"$NPM_GLOBAL_BIN:\$PATH\"" >> "$SHELL_RC"
    chown "$NEW_USER":"$NEW_USER" "$SHELL_RC"
fi

# Run the OpenClaw installer interactively as the new user.
# IMPORTANT: We download first, then execute separately.
# 'curl ... | bash' consumes stdin with the script content, leaving no stdin
# for interactive prompts. By downloading to a file first, bash's stdin remains
# the terminal, allowing the installer's interactive setup wizard to work.
# We use 'sudo -u' instead of 'su -' because sudo preserves the controlling
# terminal, while 'su -' creates a new session without one (/dev/tty fails).
INSTALL_SCRIPT=$(mktemp)
curl -fsSL https://openclaw.ai/install.sh -o "$INSTALL_SCRIPT"
chmod a+rx "$INSTALL_SCRIPT"
sudo -u "$NEW_USER" -i bash -c "export PATH=\"$NPM_GLOBAL_BIN:\$PATH\" && bash $INSTALL_SCRIPT --no-gum" || true
rm -f "$INSTALL_SCRIPT"

# Enable systemd lingering so user services persist without an active login,
# then install the OpenClaw daemon. Lingering starts the user's systemd instance
# at boot. We need to set XDG_RUNTIME_DIR and DBUS_SESSION_BUS_ADDRESS so
# 'systemctl --user' can connect to the user's D-Bus from a root context.
loginctl enable-linger "$NEW_USER"
sleep 2  # Wait for systemd to initialize the user instance

NEW_USER_UID=$(id -u "$NEW_USER")
export XDG_RUNTIME_DIR="/run/user/$NEW_USER_UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$NEW_USER_UID/bus"

sudo -u "$NEW_USER" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    PATH="$NPM_GLOBAL_BIN:$PATH" \
    bash -c "openclaw daemon install && openclaw daemon start"

# Revoke temporary passwordless sudo — user still has normal sudo via password
rm -f /etc/sudoers.d/99-openclaw-temp

echo ""
echo "================================================="
echo "✅ Server Provisioning & OpenClaw Setup Complete!"
echo "Your server is updated, fully firewalled, and running."
echo "Fail2Ban is active to protect your login endpoints."
echo ""
echo "IMPORTANT INFO:"
echo "  SSH Port: $NEW_SSH_PORT"
echo "  Username: $NEW_USER"
echo "  Server:   $SERVER_IP"
echo ""
echo "HOW TO CONNECT:"
echo "  ssh -p $NEW_SSH_PORT $NEW_USER@$SERVER_IP"
echo ""
echo "ACCESS YOUR DASHBOARD (SSH Tunnel — run from your LOCAL computer):"
echo "  ssh -p $NEW_SSH_PORT -L 18789:localhost:18789 $NEW_USER@$SERVER_IP"
echo "  Then open: http://localhost:18789"

if [ "$SSH_KEYS_DETECTED" = true ]; then
    echo ""
    echo "================================================="
    echo "🔑 SSH KEYS DETECTED — OPTIONAL SECURITY HARDENING"
    echo "================================================="
    echo "Password authentication is currently ON for your safety."
    echo "After you confirm you can log in with your SSH key,"
    echo "run this command on the server to disable password login:"
    echo ""
    echo "  sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/00-openclaw-security.conf && sudo sshd -t && sudo systemctl restart sshd"
    echo ""
    echo "⚠️  Only run this AFTER verifying key-based login works!"
fi

echo ""
echo "================================================="
echo "🔄 The server will reboot in 10 seconds to apply kernel updates."
echo "   It may take about a minute to come back online."
echo "   After reboot, reconnect with:"
echo "   ssh -p $NEW_SSH_PORT $NEW_USER@$SERVER_IP"
echo "================================================="
sleep 10
reboot
