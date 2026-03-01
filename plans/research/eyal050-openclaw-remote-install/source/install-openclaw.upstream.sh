#!/bin/bash
################################################################################
# OpenClaw Automated Installation Script for Ubuntu 24.04
# Version: 1.0.0
#
# This script automates the installation of OpenClaw on Ubuntu 24.04 (Hetzner VPS)
# with Telegram integration, Anthropic API authentication, and remote dashboard access.
#
# Usage:
#   export ANTHROPIC_API_KEY="your-api-key"
#   export TELEGRAM_BOT_TOKEN="your-bot-token"
#   chmod +x install-openclaw.sh
#   ./install-openclaw.sh
################################################################################

set -euo pipefail

#=============================================================================
# CONFIGURATION SECTION - EDIT THESE VALUES
#=============================================================================

# Required: Anthropic API Key (get from console.anthropic.com)
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

# Required: Telegram Bot Token (get from @BotFather)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"

# Optional: Gateway authentication token (auto-generated if empty)
OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"

# Installation directory
OPENCLAW_INSTALL_DIR="${HOME}/openclaw"

# Configuration directory
OPENCLAW_CONFIG_DIR="${HOME}/.openclaw"

# Workspace directory (for agent files)
OPENCLAW_WORKSPACE_DIR="${HOME}/.openclaw/workspace"

# Gateway ports
OPENCLAW_GATEWAY_PORT="18789"
OPENCLAW_BRIDGE_PORT="18790"

# Gateway network binding (options: loopback, lan)
# For remote access, use "lan"
OPENCLAW_GATEWAY_BIND="lan"

# Allow insecure HTTP access from remote IP (needed for remote access without HTTPS)
ALLOW_INSECURE_AUTH="true"

# OpenClaw version (branch/tag to checkout)
OPENCLAW_VERSION="main"

# Docker image name
OPENCLAW_IMAGE="openclaw:local"

# Optional: Additional APT packages to install in Docker image
OPENCLAW_DOCKER_APT_PACKAGES="${OPENCLAW_DOCKER_APT_PACKAGES:-}"

# Logging
LOG_DIR="${HOME}/openclaw-install-logs"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
EXTENDED_LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S)-extended.log"

# Firewall configuration
ENABLE_UFW="true"
UFW_ALLOW_FROM="any"  # Or specific IP like "203.0.113.0/24"

# Health check configuration
HEALTH_CHECK_TIMEOUT=5  # seconds between retries
HEALTH_CHECK_RETRIES=12  # number of retries (total 60 seconds)

#=============================================================================
# LOGGING FRAMEWORK
#=============================================================================

# Create log directory
mkdir -p "${LOG_DIR}"

# Logging functions
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "\033[0;32m[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*\033[0m" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "\033[0;31m[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*\033[0m" | tee -a "${LOG_FILE}" >&2
}

log_warn() {
    echo -e "\033[0;33m[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*\033[0m" | tee -a "${LOG_FILE}"
}

log_section() {
    echo "" | tee -a "${LOG_FILE}"
    echo "================================================================================" | tee -a "${LOG_FILE}"
    echo "$*" | tee -a "${LOG_FILE}"
    echo "================================================================================" | tee -a "${LOG_FILE}"
}

log_extended() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "${EXTENDED_LOG_FILE}"
}

#=============================================================================
# ERROR HANDLING
#=============================================================================

cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Installation failed with exit code: $exit_code"
        log_error "Check the log file for details: ${LOG_FILE}"
        log_error "Extended log file: ${EXTENDED_LOG_FILE}"
        log_error ""
        log_error "Last 30 lines of detailed error log:"
        log_error "----------------------------------------"
        tail -n 30 "${EXTENDED_LOG_FILE}" 2>/dev/null | while IFS= read -r line; do
            log_error "$line"
        done
        log_error "----------------------------------------"
        log_error ""
        log_error "To retry installation, fix the errors and run the script again."
        log_error "To completely remove OpenClaw, run:"
        log_error "  cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose down -v"
        log_error "  rm -rf ${OPENCLAW_INSTALL_DIR} ${OPENCLAW_CONFIG_DIR}"
    fi
}

trap cleanup_on_error EXIT

#=============================================================================
# VALIDATION FUNCTIONS
#=============================================================================

validate_os() {
    log_info "Validating operating system..."

    if [ ! -f /etc/os-release ]; then
        log_error "Cannot determine OS version. /etc/os-release not found."
        exit 1
    fi

    . /etc/os-release

    if [ "$ID" != "ubuntu" ]; then
        log_warn "This script is designed for Ubuntu. Detected: $ID"
        log_warn "Proceeding anyway, but installation may fail."
    fi

    if [ "$VERSION_ID" != "24.04" ] && [ "$VERSION_ID" != "22.04" ]; then
        log_warn "This script is optimized for Ubuntu 24.04. Detected: $VERSION_ID"
        log_warn "Proceeding anyway, but installation may fail."
    fi

    log_success "OS validated: $ID $VERSION_ID"
}

validate_parameters() {
    log_info "Validating required parameters..."

    local errors=0

    if [ -z "$ANTHROPIC_API_KEY" ]; then
        log_error "ANTHROPIC_API_KEY is not set. Please set it as an environment variable."
        log_error "Example: export ANTHROPIC_API_KEY='sk-ant-...'"
        errors=$((errors + 1))
    fi

    if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        log_error "TELEGRAM_BOT_TOKEN is not set. Please set it as an environment variable."
        log_error "Example: export TELEGRAM_BOT_TOKEN='123456789:ABC...'"
        errors=$((errors + 1))
    fi

    if [ $errors -gt 0 ]; then
        log_error "Required parameters are missing. Cannot proceed."
        exit 2
    fi

    log_success "Required parameters validated"
}

check_disk_space() {
    log_info "Checking disk space..."

    local available_gb=$(df -BG "${HOME}" | tail -1 | awk '{print $4}' | sed 's/G//')

    if [ "$available_gb" -lt 10 ]; then
        log_warn "Available disk space: ${available_gb}GB. Recommended: 10GB+"
        log_warn "Installation may fail due to insufficient disk space."
    else
        log_success "Disk space check passed: ${available_gb}GB available"
    fi
}

check_ram() {
    log_info "Checking RAM..."

    local total_ram_mb=$(free -m | grep Mem | awk '{print $2}')
    local total_ram_gb=$((total_ram_mb / 1024))

    if [ "$total_ram_mb" -lt 2048 ]; then
        log_warn "Available RAM: ${total_ram_gb}GB. Recommended: 2GB+"
        log_warn "Performance may be degraded with insufficient RAM."
    else
        log_success "RAM check passed: ${total_ram_gb}GB available"
    fi
}

#=============================================================================
# PREREQUISITE INSTALLATION FUNCTIONS
#=============================================================================

install_docker() {
    log_info "Checking Docker installation..."

    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version)
        log_info "Docker already installed: ${docker_version}"

        # Check if docker compose plugin is available
        if docker compose version &> /dev/null; then
            log_success "Docker Compose plugin is available"
            return 0
        else
            log_warn "Docker is installed but Compose plugin is missing. Installing..."
        fi
    fi

    log_info "Installing Docker..."

    # Update package index
    log_info "Updating package index..."
    sudo apt-get update >> "${EXTENDED_LOG_FILE}" 2>&1

    # Install prerequisites
    log_info "Installing prerequisites..."
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release >> "${EXTENDED_LOG_FILE}" 2>&1

    # Add Docker GPG key
    log_info "Adding Docker GPG key..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>> "${LOG_FILE}"

    # Add Docker repository
    log_info "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    log_info "Installing Docker Engine..."
    sudo apt-get update >> "${EXTENDED_LOG_FILE}" 2>&1
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "${EXTENDED_LOG_FILE}" 2>&1

    # Add current user to docker group
    log_info "Adding user ${USER} to docker group..."
    sudo usermod -aG docker "${USER}"

    log_success "Docker installed successfully"
    log_warn "You may need to log out and back in for docker group membership to take effect."
    log_warn "For this session, docker commands will use 'sudo docker' prefix."

    # Test Docker installation
    if sudo docker --version >> "${LOG_FILE}" 2>&1; then
        log_success "Docker is working correctly"
    else
        log_error "Docker installation failed. Check log for details."
        exit 1
    fi
}

install_git() {
    log_info "Checking Git installation..."

    if command -v git &> /dev/null; then
        local git_version=$(git --version)
        log_success "Git already installed: ${git_version}"
        return 0
    fi

    log_info "Installing Git..."
    sudo apt-get update >> "${EXTENDED_LOG_FILE}" 2>&1
    sudo apt-get install -y git >> "${EXTENDED_LOG_FILE}" 2>&1

    log_success "Git installed successfully"
}

install_ufw() {
    if [ "${ENABLE_UFW}" != "true" ]; then
        log_info "UFW installation skipped (ENABLE_UFW=false)"
        return 0
    fi

    log_info "Checking UFW installation..."

    if command -v ufw &> /dev/null; then
        log_success "UFW already installed"
        return 0
    fi

    log_info "Installing UFW..."
    sudo apt-get update >> "${EXTENDED_LOG_FILE}" 2>&1
    sudo apt-get install -y ufw >> "${EXTENDED_LOG_FILE}" 2>&1

    log_success "UFW installed successfully"
}

cleanup_old_installation() {
    log_info "Checking for previous OpenClaw installations..."

    local docker_cmd=$(get_docker_cmd)
    local cleanup_needed=false

    # Check if Docker containers exist
    if [ -d "${OPENCLAW_INSTALL_DIR}/openclaw" ]; then
        cd "${OPENCLAW_INSTALL_DIR}/openclaw"
        if ${docker_cmd} compose ps 2>/dev/null | grep -q "openclaw"; then
            log_info "Stopping existing Docker containers..."
            ${docker_cmd} compose down -v >> "${EXTENDED_LOG_FILE}" 2>&1 || true
            cleanup_needed=true
        fi
    fi

    # Remove old installation directory
    if [ -d "${OPENCLAW_INSTALL_DIR}" ]; then
        log_info "Removing old installation directory: ${OPENCLAW_INSTALL_DIR}"
        rm -rf "${OPENCLAW_INSTALL_DIR}"
        cleanup_needed=true
    fi

    # Remove old configuration directory
    if [ -d "${OPENCLAW_CONFIG_DIR}" ]; then
        log_info "Removing old configuration directory: ${OPENCLAW_CONFIG_DIR}"
        rm -rf "${OPENCLAW_CONFIG_DIR}"
        cleanup_needed=true
    fi

    # Clean up old log files (keep last 5)
    if [ -d "${LOG_DIR}" ]; then
        local log_count=$(ls -1 "${LOG_DIR}"/install-*.log 2>/dev/null | wc -l)
        if [ "$log_count" -gt 5 ]; then
            log_info "Cleaning up old log files (keeping last 5)..."
            ls -1t "${LOG_DIR}"/install-*.log | tail -n +6 | xargs rm -f 2>/dev/null || true
            cleanup_needed=true
        fi
    fi

    if [ "$cleanup_needed" = true ]; then
        log_success "Cleanup completed"
    else
        log_info "No previous installation found, skipping cleanup"
    fi
}

update_system() {
    log_info "Updating system packages..."

    log_info "Refreshing package lists..."
    sudo apt-get update >> "${EXTENDED_LOG_FILE}" 2>&1

    log_info "Upgrading installed packages (this may take a few minutes)..."
    sudo apt-get upgrade -y >> "${EXTENDED_LOG_FILE}" 2>&1

    log_success "System packages updated successfully"
}

#=============================================================================
# REPOSITORY SETUP FUNCTIONS
#=============================================================================

test_github_connectivity() {
    log_info "Testing GitHub connectivity..."

    # Test DNS resolution
    if ! host github.com >> "${EXTENDED_LOG_FILE}" 2>&1; then
        log_warn "Cannot resolve github.com - DNS may be misconfigured"
        log_info "Trying to resolve using: $(cat /etc/resolv.conf | grep nameserver)"
    fi

    # Test HTTPS connectivity
    if ! curl -s -I --connect-timeout 5 https://github.com >> "${EXTENDED_LOG_FILE}" 2>&1; then
        log_warn "Cannot connect to github.com via HTTPS - firewall may be blocking"
    fi

    # Test git protocol access with retry
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_info "Attempting to access OpenClaw repository (attempt $attempt/$max_attempts)..."
        if git ls-remote --exit-code https://github.com/openclaw/openclaw.git >> "${EXTENDED_LOG_FILE}" 2>&1; then
            log_success "GitHub connectivity test passed"
            return 0
        fi
        if [ $attempt -lt $max_attempts ]; then
            log_warn "Failed to access repository, retrying in 2 seconds..."
            sleep 2
        fi
        attempt=$((attempt + 1))
    done

    log_error "Cannot access OpenClaw repository after $max_attempts attempts"
    log_error "Last error captured in extended log: ${EXTENDED_LOG_FILE}"
    log_error "This could be due to:"
    log_error "  - Network connectivity issues"
    log_error "  - Firewall blocking port 443"
    log_error "  - DNS resolution problems"
    log_error "  - GitHub being temporarily unavailable"
    return 1
}

clone_openclaw_repository() {
    log_info "Setting up OpenClaw repository..."

    # Test connectivity before attempting clone
    test_github_connectivity || exit 1

    # Create installation directory
    mkdir -p "${OPENCLAW_INSTALL_DIR}"

    # Check if repository already exists
    if [ -d "${OPENCLAW_INSTALL_DIR}/openclaw" ]; then
        log_warn "OpenClaw repository already exists at ${OPENCLAW_INSTALL_DIR}/openclaw"
        log_info "Skipping clone. Using existing repository."
        cd "${OPENCLAW_INSTALL_DIR}/openclaw"

        # Update to latest version
        log_info "Pulling latest changes..."
        git fetch origin 2>&1 | tee -a "${EXTENDED_LOG_FILE}" || true
        git checkout "${OPENCLAW_VERSION}" >> "${EXTENDED_LOG_FILE}" 2>&1
        git pull origin "${OPENCLAW_VERSION}" 2>&1 | tee -a "${EXTENDED_LOG_FILE}" || true
    else
        log_info "Cloning OpenClaw repository (this may take a minute)..."

        # Retry logic for transient network failures
        local max_retries=3
        local retry_delay=5
        local attempt=1

        while [ $attempt -le $max_retries ]; do
            if [ $attempt -gt 1 ]; then
                log_info "Retry attempt $attempt of $max_retries..."
                sleep $retry_delay
            fi

            # Use tee to show output on console AND save to extended log
            if git clone --verbose --progress https://github.com/openclaw/openclaw.git "${OPENCLAW_INSTALL_DIR}/openclaw" 2>&1 | tee -a "${EXTENDED_LOG_FILE}"; then
                # Clone succeeded
                cd "${OPENCLAW_INSTALL_DIR}/openclaw"
                git checkout "${OPENCLAW_VERSION}" >> "${EXTENDED_LOG_FILE}" 2>&1
                log_success "OpenClaw repository ready at ${OPENCLAW_INSTALL_DIR}/openclaw"
                return 0
            fi

            attempt=$((attempt + 1))
        done

        # All retries failed
        log_error "Failed to clone OpenClaw repository after $max_retries attempts"
        log_error "See error details above and in: ${EXTENDED_LOG_FILE}"
        log_error ""
        log_error "Common causes and troubleshooting steps:"
        log_error "  1. Network issues - check: ping github.com"
        log_error "  2. Firewall blocking - check: sudo ufw status"
        log_error "  3. DNS problems - check: cat /etc/resolv.conf"
        log_error "  4. Proxy needed - check: git config --list | grep -i proxy"
        exit 1
    fi

    log_success "OpenClaw repository ready at ${OPENCLAW_INSTALL_DIR}/openclaw"
}

create_directory_structure() {
    log_info "Creating directory structure..."

    mkdir -p "${OPENCLAW_CONFIG_DIR}"
    mkdir -p "${OPENCLAW_WORKSPACE_DIR}"
    mkdir -p "${OPENCLAW_CONFIG_DIR}/agents/main/agent"

    log_success "Directory structure created"
}

#=============================================================================
# CONFIGURATION GENERATION FUNCTIONS
#=============================================================================

generate_gateway_token() {
    if [ -z "${OPENCLAW_GATEWAY_TOKEN}" ]; then
        log_info "Generating gateway token..."
        OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
        log_success "Gateway token generated"
    else
        log_info "Using provided gateway token"
    fi
}

create_openclaw_config() {
    log_info "Creating OpenClaw configuration file..."

    local config_file="${OPENCLAW_CONFIG_DIR}/openclaw.json"

    cat > "${config_file}" <<EOF
{
  "gateway": {
    "mode": "local",
    "port": ${OPENCLAW_GATEWAY_PORT},
    "bind": "${OPENCLAW_GATEWAY_BIND}",
    "auth": {
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    },
    "controlUi": {
      "allowInsecureAuth": ${ALLOW_INSECURE_AUTH}
    }
  },
  "agents": {
    "defaults": {
      "workspace": "${OPENCLAW_WORKSPACE_DIR}",
      "model": {
        "primary": "anthropic/claude-sonnet-4-5"
      }
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groupPolicy": "disabled"
    }
  },
  "auth": {
    "profiles": {
      "anthropic-main": {
        "provider": "anthropic",
        "mode": "api_key"
      }
    },
    "order": {
      "anthropic": ["anthropic-main"]
    }
  }
}
EOF

    chmod 600 "${config_file}"
    log_success "OpenClaw configuration created at ${config_file}"
}

create_auth_profiles() {
    log_info "Creating authentication profiles..."

    local auth_file="${OPENCLAW_CONFIG_DIR}/agents/main/agent/auth-profiles.json"

    mkdir -p "$(dirname "${auth_file}")"

    cat > "${auth_file}" <<EOF
{
  "anthropic-main": {
    "provider": "anthropic",
    "apiKey": "${ANTHROPIC_API_KEY}",
    "mode": "api_key"
  }
}
EOF

    chmod 600 "${auth_file}"
    log_success "Authentication profiles created at ${auth_file}"
}

create_env_file() {
    log_info "Creating .env file for Docker Compose..."

    local env_file="${OPENCLAW_INSTALL_DIR}/openclaw/.env"

    cat > "${env_file}" <<EOF
# OpenClaw Environment Configuration
# Generated on $(date)

ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
OPENCLAW_GATEWAY_BIND=${OPENCLAW_GATEWAY_BIND}
OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT}
OPENCLAW_BRIDGE_PORT=${OPENCLAW_BRIDGE_PORT}
OPENCLAW_CONFIG_DIR=${OPENCLAW_CONFIG_DIR}
OPENCLAW_WORKSPACE_DIR=${OPENCLAW_WORKSPACE_DIR}
OPENCLAW_IMAGE=${OPENCLAW_IMAGE}
OPENCLAW_DOCKER_APT_PACKAGES=${OPENCLAW_DOCKER_APT_PACKAGES}
EOF

    chmod 600 "${env_file}"
    log_success ".env file created at ${env_file}"
}

fix_config_permissions() {
    log_info "Setting proper ownership for configuration files..."

    # Change ownership of entire .openclaw directory to uid 1000 (node user in container)
    # uid 1000 = node user in Docker container (see Dockerfile line 40: USER node)
    # This allows the containerized application to read its configuration files
    sudo chown -R 1000:1000 "${OPENCLAW_CONFIG_DIR}"

    log_success "Configuration file ownership set to uid 1000 (node user)"
}

#=============================================================================
# DOCKER DEPLOYMENT FUNCTIONS
#=============================================================================

# Determine docker command (with or without sudo)
get_docker_cmd() {
    if groups | grep -q docker; then
        echo "docker"
    else
        echo "sudo docker"
    fi
}

deploy_with_docker() {
    log_info "Deploying OpenClaw with Docker Compose..."

    cd "${OPENCLAW_INSTALL_DIR}/openclaw"

    local docker_cmd=$(get_docker_cmd)

    # Build the OpenClaw Docker image
    # Note: docker-compose.yml doesn't have a build: section, so we need to use docker build directly
    log_info "Building OpenClaw Docker image (this may take 10-15 minutes)..."
    ${docker_cmd} build \
        --build-arg "OPENCLAW_DOCKER_APT_PACKAGES=${OPENCLAW_DOCKER_APT_PACKAGES:-}" \
        -t "${OPENCLAW_IMAGE}" \
        -f "${OPENCLAW_INSTALL_DIR}/openclaw/Dockerfile" \
        "${OPENCLAW_INSTALL_DIR}/openclaw" >> "${EXTENDED_LOG_FILE}" 2>&1

    if [ $? -eq 0 ]; then
        log_success "Docker image built successfully: ${OPENCLAW_IMAGE}"
    else
        log_error "Failed to build Docker image"
        log_error "Check the log file for details: ${LOG_FILE}"
        return 1
    fi

    # Start services
    log_info "Starting OpenClaw services..."
    ${docker_cmd} compose up -d >> "${LOG_FILE}" 2>&1

    log_success "OpenClaw services started"

    # Wait for containers to initialize
    log_info "Waiting for containers to initialize (10 seconds)..."
    sleep 10
}

verify_containers() {
    log_info "Verifying container status..."

    cd "${OPENCLAW_INSTALL_DIR}/openclaw"

    local docker_cmd=$(get_docker_cmd)

    if ${docker_cmd} compose ps | grep -q "openclaw-gateway.*Up\|openclaw-gateway.*running"; then
        log_success "openclaw-gateway container is running"
    else
        log_error "openclaw-gateway container is not running"
        log_error "Container status:"
        ${docker_cmd} compose ps | tee -a "${LOG_FILE}"
        log_error "Recent logs:"
        ${docker_cmd} compose logs --tail=50 openclaw-gateway | tee -a "${LOG_FILE}"
        return 1
    fi
}

#=============================================================================
# SECURITY CONFIGURATION FUNCTIONS
#=============================================================================

configure_firewall() {
    if [ "${ENABLE_UFW}" != "true" ]; then
        log_info "Firewall configuration skipped (ENABLE_UFW=false)"
        return 0
    fi

    log_info "Configuring UFW firewall..."

    # Check if UFW is already enabled
    if sudo ufw status | grep -q "Status: active"; then
        log_info "UFW is already active"
    else
        # Allow SSH first (critical!)
        log_info "Allowing SSH (port 22)..."
        sudo ufw allow 22/tcp >> "${LOG_FILE}" 2>&1

        # Enable firewall (with --force to avoid interactive prompt)
        log_info "Enabling UFW..."
        sudo ufw --force enable >> "${LOG_FILE}" 2>&1
    fi

    # Allow OpenClaw Gateway port
    log_info "Allowing OpenClaw Gateway (port ${OPENCLAW_GATEWAY_PORT})..."
    if [ "${UFW_ALLOW_FROM}" = "any" ]; then
        sudo ufw allow ${OPENCLAW_GATEWAY_PORT}/tcp >> "${LOG_FILE}" 2>&1
    else
        sudo ufw allow from ${UFW_ALLOW_FROM} to any port ${OPENCLAW_GATEWAY_PORT} proto tcp >> "${LOG_FILE}" 2>&1
    fi

    # Show status
    log_success "Firewall configured successfully"
    log_info "Firewall status:"
    sudo ufw status | tee -a "${LOG_FILE}"
}

#=============================================================================
# VERIFICATION FUNCTIONS
#=============================================================================

verify_installation() {
    log_info "Verifying installation..."

    cd "${OPENCLAW_INSTALL_DIR}/openclaw"

    local docker_cmd=$(get_docker_cmd)

    # Wait for gateway to be ready
    log_info "Waiting for gateway to become ready (up to 60 seconds)..."
    local retries=0
    while [ $retries -lt ${HEALTH_CHECK_RETRIES} ]; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${OPENCLAW_GATEWAY_PORT}/" | grep -q "200\|401"; then
            log_success "Gateway is responding on port ${OPENCLAW_GATEWAY_PORT}"
            return 0
        fi
        retries=$((retries + 1))
        log_info "Waiting... (attempt $retries/${HEALTH_CHECK_RETRIES})"
        sleep ${HEALTH_CHECK_TIMEOUT}
    done

    log_error "Gateway did not become ready within timeout"
    log_error "Showing recent gateway logs:"
    ${docker_cmd} compose logs --tail=50 openclaw-gateway | tee -a "${LOG_FILE}"
    return 1
}

#=============================================================================
# TELEGRAM AUTO-PAIRING
#=============================================================================

auto_approve_telegram_pairing() {
    # Skip if no Telegram token configured
    if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        log_info "Skipping Telegram pairing (no bot token configured)"
        return 0
    fi

    log_section "Automated Telegram Pairing"
    log_info "Checking for pending pairing requests..."

    local pairing_file="${OPENCLAW_CONFIG_DIR}/credentials/telegram-pairing.json"

    # Wait a bit for bot to potentially receive messages
    sleep 5

    # Check if pairing file exists
    if [ ! -f "$pairing_file" ]; then
        log_info "No pairing file found yet. Please send a message to your bot first."
        log_info "Bot username: $(get_telegram_bot_username)"
        log_info "Then run: ${OPENCLAW_INSTALL_DIR}/openclaw/scripts/telegram-pairing-helper.sh"
        return 0
    fi

    # Check for pending requests using jq
    if ! command -v jq &> /dev/null; then
        log_warn "jq not installed, skipping auto-pairing"
        log_info "Run: ${OPENCLAW_INSTALL_DIR}/openclaw/scripts/telegram-pairing-helper.sh"
        return 0
    fi

    local pending_count=$(jq '.requests | length' "$pairing_file" 2>/dev/null || echo "0")

    if [ "$pending_count" -eq 0 ]; then
        log_info "No pending pairing requests found"
        log_info "Send a message to your bot to generate a pairing request"
        return 0
    fi

    log_info "Found $pending_count pending pairing request(s)"

    # Create Python script to approve pairing (OpenClaw uses separate allowFrom file)
    local approve_script="/tmp/openclaw_approve_pairing_$$.py"
    cat > "$approve_script" <<'PYTHON_EOF'
import json
import sys
import os
from pathlib import Path

pairing_file = sys.argv[1]
credentials_dir = os.path.dirname(pairing_file)

# Read pairing file
with open(pairing_file, "r") as f:
    pairing_data = json.load(f)

requests = pairing_data.get("requests", [])
if not requests:
    print("No pending requests to approve")
    sys.exit(0)

# Extract user IDs and metadata
approved_ids = []
for request in requests:
    user_id = request.get("id")
    code = request.get("code")
    account_id = request.get("meta", {}).get("accountId", "default")

    if user_id:
        approved_ids.append(user_id)
        print(f"✓ Approving user {user_id} (code: {code}, account: {account_id})")

# Create allowFrom file (OpenClaw pairing system uses this separate file)
# Format: telegram-{accountId}-allowFrom.json or telegram-allowFrom.json
allowfrom_file = os.path.join(credentials_dir, "telegram-default-allowFrom.json")

# Read existing allowFrom or create new
if os.path.exists(allowfrom_file):
    with open(allowfrom_file, "r") as f:
        allowfrom_data = json.load(f)
else:
    allowfrom_data = {"version": 1, "allowFrom": []}

# Add new IDs to allowFrom
existing = set(allowfrom_data.get("allowFrom", []))
for user_id in approved_ids:
    if user_id not in existing:
        allowfrom_data["allowFrom"].append(user_id)

# Write allowFrom file
with open(allowfrom_file, "w") as f:
    json.dump(allowfrom_data, f, indent=2)

# Clear requests from pairing file
pairing_data["requests"] = []
with open(pairing_file, "w") as f:
    json.dump(pairing_data, f, indent=2)

print(f"\n✓ Successfully approved {len(approved_ids)} user(s)")
print(f"✓ Created/updated {allowfrom_file}")
PYTHON_EOF

    # Stop gateway before modifying pairing file
    log_info "Stopping gateway to modify pairing file..."
    cd "${OPENCLAW_INSTALL_DIR}/openclaw"
    local docker_cmd=$(get_docker_cmd)
    ${docker_cmd} compose stop openclaw-gateway >> "${EXTENDED_LOG_FILE}" 2>&1

    # Execute the approval script
    if python3 "$approve_script" "$pairing_file"; then
        log_success "Telegram pairing approved successfully!"

        # CRITICAL: Set correct ownership for container user (uid:gid 1000:1000)
        log_info "Setting correct file ownership..."
        chown 1000:1000 "$pairing_file"
        chmod 600 "$pairing_file"

        # Start gateway to load approved pairing
        log_info "Starting gateway with approved pairing..."
        ${docker_cmd} compose start openclaw-gateway >> "${EXTENDED_LOG_FILE}" 2>&1
        sleep 5

        log_success "Gateway started. Telegram bot is now ready to use!"
    else
        log_error "Failed to approve pairing automatically"
        log_info "You can approve manually using:"
        log_info "  ${OPENCLAW_INSTALL_DIR}/openclaw/scripts/telegram-pairing-helper.sh"

        # Restart gateway even if approval failed
        log_info "Restarting gateway..."
        ${docker_cmd} compose start openclaw-gateway >> "${EXTENDED_LOG_FILE}" 2>&1
    fi

    # Cleanup
    rm -f "$approve_script"
}

get_telegram_bot_username() {
    if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
        local response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" 2>/dev/null || echo '{}')
        local username=$(echo "$response" | jq -r '.result.username // "your_bot"' 2>/dev/null || echo "your_bot")
        echo "@$username"
    else
        echo "@your_bot"
    fi
}

#=============================================================================
# POST-INSTALLATION DISPLAY
#=============================================================================

display_completion_message() {
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

    log_section "OpenClaw Installation Complete!"

    cat <<EOF | tee -a "${LOG_FILE}"

Access Information:
-------------------
Dashboard URL: http://${server_ip}:${OPENCLAW_GATEWAY_PORT}
Gateway Token: ${OPENCLAW_GATEWAY_TOKEN}

How to Access the Dashboard:
-----------------------------
1. Open your browser on your Windows 11 laptop
2. Navigate to: http://${server_ip}:${OPENCLAW_GATEWAY_PORT}
3. When prompted, enter the gateway token shown above
4. You should see the OpenClaw Control UI

Telegram Bot Setup:
-------------------
Status: Automatic pairing was attempted during installation

If you see "access not configured" errors:
1. Send a message to your bot to generate a pairing request
2. Fix automatically with:
   ./scripts/fix-telegram-pairing.sh

Alternative pairing methods:
- Dashboard: http://${server_ip}:${OPENCLAW_GATEWAY_PORT}
- Helper script: ./scripts/telegram-pairing-helper.sh

For fully automated installation with pairing, use:
  ./unified-install-openclaw.sh --telegram-token "..." --telegram-auto-pairing yes

Container Management Commands:
------------------------------
Start services:  cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose up -d
Stop services:   cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose down
Restart gateway: cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose restart openclaw-gateway
View logs:       cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose logs -f openclaw-gateway
Check status:    cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose ps

Configuration Files:
--------------------
Main config:     ${OPENCLAW_CONFIG_DIR}/openclaw.json
Auth profiles:   ${OPENCLAW_CONFIG_DIR}/agents/main/agent/auth-profiles.json
Environment:     ${OPENCLAW_INSTALL_DIR}/openclaw/.env
Workspace:       ${OPENCLAW_WORKSPACE_DIR}

Log Files:
----------
Main log:        ${LOG_FILE}
Extended log:    ${EXTENDED_LOG_FILE}

Troubleshooting:
----------------
If the dashboard is not accessible:
1. Check container status:
   cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose ps

2. Check gateway logs:
   cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose logs openclaw-gateway

3. Verify firewall:
   sudo ufw status

4. Check port binding:
   sudo netstat -tlnp | grep ${OPENCLAW_GATEWAY_PORT}

5. Review installation log:
   cat ${LOG_FILE}

Security Warning:
-----------------
⚠️  The gateway is configured to allow remote HTTP access (allowInsecureAuth: true).
    This is acceptable for personal use, but for production deployments, consider:
    - Setting up HTTPS with a reverse proxy (Caddy/Nginx)
    - Using a VPN for access
    - Restricting firewall rules to specific IP addresses

Next Steps:
-----------
1. Access the dashboard and verify it's working
2. Set up your Telegram bot and test messaging
3. Explore the OpenClaw documentation: https://docs.openclaw.ai/
4. Install additional skills from the marketplace
5. Customize your agent's behavior

================================================================================

EOF
}

#=============================================================================
# MAIN INSTALLATION FLOW
#=============================================================================

main() {
    log_section "OpenClaw Installation Script v1.0.0"
    log_info "Starting installation on $(date)"
    log_info "Log file: ${LOG_FILE}"
    log_info "Extended log file: ${EXTENDED_LOG_FILE}"

    # Phase 0: Cleanup and System Update
    log_section "Phase 0: Cleanup and System Update"
    cleanup_old_installation
    update_system

    # Phase 1: Validation
    log_section "Phase 1: System Validation"
    validate_os
    validate_parameters
    check_disk_space
    check_ram

    # Phase 2: Prerequisites
    log_section "Phase 2: Installing Prerequisites"
    install_docker
    install_git
    install_ufw

    # Phase 3: Repository Setup
    log_section "Phase 3: Repository Setup"
    clone_openclaw_repository
    create_directory_structure

    # Phase 4: Configuration Generation
    log_section "Phase 4: Configuration Generation"
    generate_gateway_token
    create_openclaw_config
    create_auth_profiles
    create_env_file
    fix_config_permissions

    # Phase 5: Docker Deployment
    log_section "Phase 5: Docker Deployment"
    deploy_with_docker
    verify_containers

    # Phase 6: Security Configuration
    log_section "Phase 6: Security Configuration"
    configure_firewall

    # Phase 7: Verification
    log_section "Phase 7: Installation Verification"
    verify_installation

    # Phase 8: Telegram Auto-Pairing
    auto_approve_telegram_pairing

    # Phase 9: Completion
    display_completion_message

    log_success "Installation completed successfully!"
}

# Run main installation
main
