#!/bin/bash
################################################################################
# Unified OpenClaw Installation Script
# Version: 2.0.0
#
# A comprehensive installation script that supports:
# - Local and remote installation modes
# - Multiple AI providers (Anthropic, OpenAI, Gemini)
# - Telegram channel integration
# - Workspace preservation across reinstalls
# - Automated troubleshooting and verification
#
# Usage Examples:
#
#   # Interactive local installation
#   ./unified-install-openclaw.sh
#
#   # Local with all providers via CLI
#   ./unified-install-openclaw.sh \
#     --anthropic-key "sk-ant-..." \
#     --telegram-token "123:ABC..." \
#     --openai-key "sk-proj-..." \
#     --gemini-key "AIza..."
#
#   # Remote installation with password auth
#   ./unified-install-openclaw.sh \
#     --mode remote \
#     --ssh-host root@1.2.3.4 \
#     --ssh-auth password \
#     --ssh-password "mypass" \
#     --anthropic-key "sk-ant-..."
#
#   # Reinstall preserving workspace
#   ./unified-install-openclaw.sh \
#     --preserve-workspace \
#     --anthropic-key "sk-ant-..."
#
################################################################################

set -euo pipefail

#=============================================================================
# SECTION 1: HEADER & DOCUMENTATION
#=============================================================================

# Script version
SCRIPT_VERSION="2.0.0"

# Script description
script_usage() {
    cat <<EOF
Unified OpenClaw Installation Script v${SCRIPT_VERSION}

USAGE:
    $0 [OPTIONS]

OPTIONS:
    Execution Mode:
        --mode <local|remote>              Execution mode (default: local)

    Required (Anthropic API):
        --anthropic-key <key>              Anthropic API key (required)

    Optional (AI Providers):
        --openai-key <key>                 OpenAI API key (optional)
        --gemini-key <key>                 Google Gemini API key (optional)
        --codex-key <key>                  OpenAI Codex API key (optional, defaults to openai-key)
        --codex-auth <api_key|cli_signin>  Codex authentication method (default: api_key)
        --brain-model <provider/model>     Primary brain model (default: anthropic/claude-opus-4-6)

    Optional (Channels):
        --telegram-token <token>           Telegram bot token (optional)
        --telegram-auto-pairing <yes|no|prompt>  Auto-approve Telegram pairing (default: prompt)

    Remote Mode Options (required if --mode remote):
        --ssh-host <user@host>             SSH host (e.g., root@1.2.3.4)
        --ssh-auth <password|key>          SSH authentication method
        --ssh-password <password>          SSH password (if auth=password)
        --ssh-key <path>                   SSH key path (if auth=key, default: ~/.ssh/id_rsa)

    Installation Options:
        --preserve-workspace               Preserve workspace across reinstalls
        --install-dir <path>               Installation directory (default: ~/openclaw)
        --config-dir <path>                Configuration directory (default: ~/.openclaw)
        --gateway-port <port>              Gateway port (default: 18789)

    Utility:
        --diagnose                         Run diagnostics on existing installation
        --help                             Show this help message

EXAMPLES:
    # Interactive local installation
    $0

    # Local installation with all providers
    $0 --anthropic-key "sk-ant-..." --telegram-token "123:ABC..."

    # Remote installation with password
    $0 --mode remote --ssh-host root@1.2.3.4 --ssh-auth password \\
       --ssh-password "mypass" --anthropic-key "sk-ant-..."

    # Reinstall preserving workspace
    $0 --preserve-workspace --anthropic-key "sk-ant-..."

EOF
}

#=============================================================================
# SECTION 2: CONFIGURATION VARIABLES
#=============================================================================

# Execution mode
EXECUTION_MODE="${EXECUTION_MODE:-local}"  # local|remote

# Required: Anthropic API Key
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

# Optional: Additional AI providers
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
GEMINI_API_KEY="${GEMINI_API_KEY:-}"

# Optional: Codex configuration
CODEX_API_KEY="${CODEX_API_KEY:-}"
CODEX_AUTH_METHOD="${CODEX_AUTH_METHOD:-}"  # api_key|cli_signin

# Brain/Hands model architecture
BRAIN_MODEL="${BRAIN_MODEL:-anthropic/claude-opus-4-6}"

# Optional: Telegram Bot Token
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_AUTO_PAIRING="${TELEGRAM_AUTO_PAIRING:-prompt}"  # prompt|yes|no

# Remote SSH Configuration (only needed if mode=remote)
REMOTE_SSH_HOST="${REMOTE_SSH_HOST:-}"
REMOTE_SSH_AUTH_METHOD="${REMOTE_SSH_AUTH_METHOD:-key}"  # password|key
REMOTE_SSH_PASSWORD="${REMOTE_SSH_PASSWORD:-}"
REMOTE_SSH_KEY_PATH="${REMOTE_SSH_KEY_PATH:-${HOME}/.ssh/id_rsa}"

# Installation directories
OPENCLAW_INSTALL_DIR="${OPENCLAW_INSTALL_DIR:-${HOME}/openclaw}"
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-${HOME}/.openclaw}"
OPENCLAW_WORKSPACE_DIR="${OPENCLAW_CONFIG_DIR}/workspace"
OPENCLAW_BACKUP_DIR="${HOME}/.openclaw-backups"

# Gateway configuration
OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
OPENCLAW_BRIDGE_PORT="${OPENCLAW_BRIDGE_PORT:-18790}"
OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-lan}"
# NOTE: HTTP-only mode. For production, use HTTPS via a reverse proxy (Caddy/Nginx).
ALLOW_INSECURE_AUTH="true"

# Gateway token (auto-generated if empty)
OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"

# Memory preservation
PRESERVE_WORKSPACE="${PRESERVE_WORKSPACE:-prompt}"  # prompt|yes|no

# OpenClaw version
OPENCLAW_VERSION="main"
OPENCLAW_IMAGE="openclaw:local"
OPENCLAW_DOCKER_APT_PACKAGES="${OPENCLAW_DOCKER_APT_PACKAGES:-}"

# Logging
LOG_DIR="${HOME}/openclaw-install-logs"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
EXTENDED_LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S)-extended.log"

# Firewall
ENABLE_UFW="true"
UFW_ALLOW_FROM="any"

# Health checks
HEALTH_CHECK_TIMEOUT=5
HEALTH_CHECK_RETRIES=12

# Diagnostic mode flag
DIAGNOSTIC_MODE=false

#=============================================================================
# SECTION 3: UTILITY FUNCTIONS
#=============================================================================

# Create log directory and initialize log files
mkdir -p "${LOG_DIR}"
touch "${LOG_FILE}"
touch "${EXTENDED_LOG_FILE}"

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

# Error handling
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
    fi
}

trap cleanup_on_error EXIT

# Prompt user with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local response

    if [ -n "$default" ]; then
        read -p "${prompt} [${default}]: " response
        echo "${response:-$default}"
    else
        read -p "${prompt}: " response
        echo "${response}"
    fi
}

# Prompt for password securely (hidden input)
prompt_password() {
    local prompt="$1"
    local password

    read -s -p "${prompt}: " password
    echo ""  # New line after hidden input
    echo "${password}"
}

# Validate API key format
validate_api_key() {
    local key="$1"
    local provider="$2"

    case "$provider" in
        anthropic)
            if [[ "$key" =~ ^sk-ant- ]]; then
                return 0
            fi
            ;;
        openai)
            if [[ "$key" =~ ^sk- ]]; then
                return 0
            fi
            ;;
        gemini)
            if [[ "$key" =~ ^AIza ]]; then
                return 0
            fi
            ;;
    esac

    return 1
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                EXECUTION_MODE="$2"
                shift 2
                ;;
            --anthropic-key)
                ANTHROPIC_API_KEY="$2"
                shift 2
                ;;
            --openai-key)
                OPENAI_API_KEY="$2"
                shift 2
                ;;
            --gemini-key)
                GEMINI_API_KEY="$2"
                shift 2
                ;;
            --telegram-token)
                TELEGRAM_BOT_TOKEN="$2"
                shift 2
                ;;
            --telegram-auto-pairing)
                TELEGRAM_AUTO_PAIRING="$2"
                shift 2
                ;;
            --ssh-host)
                REMOTE_SSH_HOST="$2"
                shift 2
                ;;
            --ssh-auth)
                REMOTE_SSH_AUTH_METHOD="$2"
                shift 2
                ;;
            --ssh-password)
                REMOTE_SSH_PASSWORD="$2"
                shift 2
                ;;
            --ssh-key)
                REMOTE_SSH_KEY_PATH="$2"
                shift 2
                ;;
            --preserve-workspace)
                PRESERVE_WORKSPACE="yes"
                shift
                ;;
            --install-dir)
                OPENCLAW_INSTALL_DIR="$2"
                shift 2
                ;;
            --config-dir)
                OPENCLAW_CONFIG_DIR="$2"
                OPENCLAW_WORKSPACE_DIR="${OPENCLAW_CONFIG_DIR}/workspace"
                shift 2
                ;;
            --gateway-port)
                OPENCLAW_GATEWAY_PORT="$2"
                shift 2
                ;;
            --codex-key)
                CODEX_API_KEY="$2"
                shift 2
                ;;
            --codex-auth)
                CODEX_AUTH_METHOD="$2"
                shift 2
                ;;
            --brain-model)
                BRAIN_MODEL="$2"
                shift 2
                ;;
            --diagnose)
                DIAGNOSTIC_MODE=true
                shift
                ;;
            --help)
                script_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                script_usage
                exit 1
                ;;
        esac
    done
}

#=============================================================================
# SECTION 4: MEMORY MANAGEMENT FUNCTIONS
#=============================================================================

# Backup workspace before cleanup
backup_workspace() {
    if [ ! -d "${OPENCLAW_WORKSPACE_DIR}" ]; then
        log_info "No existing workspace to backup"
        return 0
    fi

    log_info "Backing up workspace..."

    local backup_name="workspace-$(date +%Y%m%d-%H%M%S)"
    local backup_path="${OPENCLAW_BACKUP_DIR}/${backup_name}"

    mkdir -p "${OPENCLAW_BACKUP_DIR}"

    cp -r "${OPENCLAW_WORKSPACE_DIR}" "${backup_path}"

    # Store latest backup path
    echo "${backup_path}" > "${OPENCLAW_BACKUP_DIR}/latest"

    log_success "Workspace backed up to: ${backup_path}"

    # Keep only last 5 backups
    local backup_count=$(ls -1d "${OPENCLAW_BACKUP_DIR}"/workspace-* 2>/dev/null | wc -l)
    if [ "$backup_count" -gt 5 ]; then
        log_info "Cleaning up old backups (keeping last 5)..."
        ls -1td "${OPENCLAW_BACKUP_DIR}"/workspace-* | tail -n +6 | xargs rm -rf 2>/dev/null || true
    fi
}

# Restore workspace after installation
restore_workspace() {
    local latest_backup="${OPENCLAW_BACKUP_DIR}/latest"

    if [ ! -f "$latest_backup" ]; then
        log_info "No backup to restore"
        return 0
    fi

    local backup_path=$(cat "$latest_backup")

    if [ ! -d "$backup_path" ]; then
        log_warn "Backup path not found: ${backup_path}"
        return 1
    fi

    log_info "Restoring workspace from backup..."

    mkdir -p "${OPENCLAW_WORKSPACE_DIR}"
    cp -r "${backup_path}"/* "${OPENCLAW_WORKSPACE_DIR}/" 2>/dev/null || true

    # Fix permissions (uid 1000 = node user in container)
    sudo chown -R 1000:1000 "${OPENCLAW_WORKSPACE_DIR}"

    log_success "Workspace restored from: ${backup_path}"
}

# Smart cleanup with workspace preservation
cleanup_old_installation() {
    log_info "Checking for previous OpenClaw installations..."

    local docker_cmd=$(get_docker_cmd)
    local cleanup_needed=false
    local should_backup=false

    # Check if workspace exists
    if [ -d "${OPENCLAW_WORKSPACE_DIR}" ] && [ "$(ls -A "${OPENCLAW_WORKSPACE_DIR}" 2>/dev/null)" ]; then
        # Ask user about workspace preservation
        if [ "$PRESERVE_WORKSPACE" = "prompt" ]; then
            echo ""
            log_info "Existing workspace detected at: ${OPENCLAW_WORKSPACE_DIR}"
            log_info "This contains your agent's memory and conversation history."
            echo ""
            read -p "Would you like to preserve this workspace? (Y/n): " preserve_response
            if [[ "$preserve_response" =~ ^[Nn] ]]; then
                PRESERVE_WORKSPACE="no"
            else
                PRESERVE_WORKSPACE="yes"
            fi
        fi

        if [ "$PRESERVE_WORKSPACE" = "yes" ]; then
            should_backup=true
        fi
    fi

    # Backup workspace if needed
    if [ "$should_backup" = true ]; then
        backup_workspace
    fi

    # Stop Docker containers
    if [ -d "${OPENCLAW_INSTALL_DIR}/openclaw" ]; then
        cd "${OPENCLAW_INSTALL_DIR}/openclaw"
        if ${docker_cmd} compose ps 2>/dev/null | grep -q "openclaw"; then
            log_info "Stopping existing Docker containers..."
            ${docker_cmd} compose down -v >> "${EXTENDED_LOG_FILE}" 2>&1 || true
            cleanup_needed=true
        fi
        # Return to safe directory before removing installation directory
        cd "${HOME}"
    fi

    # Remove old installation directory
    if [ -d "${OPENCLAW_INSTALL_DIR}" ]; then
        log_info "Removing old installation directory: ${OPENCLAW_INSTALL_DIR}"
        rm -rf "${OPENCLAW_INSTALL_DIR}"
        cleanup_needed=true
    fi

    # Remove old configuration directory (but preserve workspace if flagged)
    if [ -d "${OPENCLAW_CONFIG_DIR}" ]; then
        log_info "Removing old configuration directory: ${OPENCLAW_CONFIG_DIR}"

        # Temporarily move workspace out if preserving
        if [ "$PRESERVE_WORKSPACE" = "yes" ] && [ -d "${OPENCLAW_WORKSPACE_DIR}" ]; then
            local temp_workspace="/tmp/openclaw-workspace-preserve"
            mv "${OPENCLAW_WORKSPACE_DIR}" "$temp_workspace" 2>/dev/null || true
            rm -rf "${OPENCLAW_CONFIG_DIR}"
            mkdir -p "${OPENCLAW_CONFIG_DIR}"
            mv "$temp_workspace" "${OPENCLAW_WORKSPACE_DIR}" 2>/dev/null || true
        else
            rm -rf "${OPENCLAW_CONFIG_DIR}"
        fi

        cleanup_needed=true
    fi

    if [ "$cleanup_needed" = true ]; then
        log_success "Cleanup completed"
    else
        log_info "No previous installation found, skipping cleanup"
    fi
}

#=============================================================================
# SECTION 5: INSTALLATION FUNCTIONS
#=============================================================================

# Validate OS
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

# Validate parameters
validate_parameters() {
    log_info "Validating required parameters..."

    local errors=0

    if [ -z "$ANTHROPIC_API_KEY" ]; then
        log_error "ANTHROPIC_API_KEY is required"
        errors=$((errors + 1))
    fi

    if [ "$EXECUTION_MODE" = "remote" ]; then
        if [ -z "$REMOTE_SSH_HOST" ]; then
            log_error "REMOTE_SSH_HOST is required for remote mode"
            errors=$((errors + 1))
        fi

        if [ "$REMOTE_SSH_AUTH_METHOD" = "password" ] && [ -z "$REMOTE_SSH_PASSWORD" ]; then
            log_error "REMOTE_SSH_PASSWORD is required when using password authentication"
            errors=$((errors + 1))
        fi

        if [ "$REMOTE_SSH_AUTH_METHOD" = "key" ] && [ ! -f "$REMOTE_SSH_KEY_PATH" ]; then
            log_error "SSH key not found at: ${REMOTE_SSH_KEY_PATH}"
            errors=$((errors + 1))
        fi
    fi

    if [ $errors -gt 0 ]; then
        log_error "Validation failed. Cannot proceed."
        exit 2
    fi

    log_success "Required parameters validated"
}

# Check disk space
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

# Check RAM
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

# Install Docker
install_docker() {
    log_info "Checking Docker installation..."

    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version)
        log_info "Docker already installed: ${docker_version}"

        if docker compose version &> /dev/null; then
            log_success "Docker Compose plugin is available"
            return 0
        else
            log_warn "Docker is installed but Compose plugin is missing. Installing..."
        fi
    fi

    log_info "Installing Docker..."

    sudo apt-get update >> "${EXTENDED_LOG_FILE}" 2>&1
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release >> "${EXTENDED_LOG_FILE}" 2>&1

    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>> "${LOG_FILE}"

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update >> "${EXTENDED_LOG_FILE}" 2>&1
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "${EXTENDED_LOG_FILE}" 2>&1

    sudo usermod -aG docker "${USER}"

    log_success "Docker installed successfully"
    log_warn "You may need to log out and back in for docker group membership to take effect."
}

# Install Git
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

# Install UFW
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

# Update system
update_system() {
    log_info "Updating system packages..."

    sudo apt-get update >> "${EXTENDED_LOG_FILE}" 2>&1
    sudo apt-get upgrade -y >> "${EXTENDED_LOG_FILE}" 2>&1

    log_success "System packages updated successfully"
}

# Test GitHub connectivity
test_github_connectivity() {
    log_info "Testing GitHub connectivity..."

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
    return 1
}

# Clone OpenClaw repository
clone_openclaw_repository() {
    log_info "Setting up OpenClaw repository..."

    test_github_connectivity || exit 1

    mkdir -p "${OPENCLAW_INSTALL_DIR}"

    if [ -d "${OPENCLAW_INSTALL_DIR}/openclaw" ]; then
        log_warn "OpenClaw repository already exists at ${OPENCLAW_INSTALL_DIR}/openclaw"
        log_info "Updating to latest version..."
        cd "${OPENCLAW_INSTALL_DIR}/openclaw"
        git fetch origin 2>&1 | tee -a "${EXTENDED_LOG_FILE}" || true
        git checkout "${OPENCLAW_VERSION}" >> "${EXTENDED_LOG_FILE}" 2>&1
        git pull origin "${OPENCLAW_VERSION}" 2>&1 | tee -a "${EXTENDED_LOG_FILE}" || true
    else
        log_info "Cloning OpenClaw repository..."

        local max_retries=3
        local attempt=1

        while [ $attempt -le $max_retries ]; do
            if [ $attempt -gt 1 ]; then
                log_info "Retry attempt $attempt of $max_retries..."
                sleep 5
            fi

            if git clone --verbose --progress https://github.com/openclaw/openclaw.git "${OPENCLAW_INSTALL_DIR}/openclaw" 2>&1 | tee -a "${EXTENDED_LOG_FILE}"; then
                cd "${OPENCLAW_INSTALL_DIR}/openclaw"
                git checkout "${OPENCLAW_VERSION}" >> "${EXTENDED_LOG_FILE}" 2>&1
                log_success "OpenClaw repository ready"
                return 0
            fi

            attempt=$((attempt + 1))
        done

        log_error "Failed to clone OpenClaw repository after $max_retries attempts"
        exit 1
    fi

    log_success "OpenClaw repository ready at ${OPENCLAW_INSTALL_DIR}/openclaw"
}

# Create directory structure
create_directory_structure() {
    log_info "Creating directory structure..."

    mkdir -p "${OPENCLAW_CONFIG_DIR}"
    mkdir -p "${OPENCLAW_WORKSPACE_DIR}"
    mkdir -p "${OPENCLAW_CONFIG_DIR}/agents/main/agent"

    log_success "Directory structure created"
}

# Determine docker command
get_docker_cmd() {
    if groups | grep -q docker; then
        echo "docker"
    else
        echo "sudo docker"
    fi
}

# Deploy with Docker
deploy_with_docker() {
    log_info "Deploying OpenClaw with Docker Compose..."

    cd "${OPENCLAW_INSTALL_DIR}/openclaw"

    local docker_cmd=$(get_docker_cmd)

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
        return 1
    fi

    log_info "Starting OpenClaw services..."
    ${docker_cmd} compose up -d >> "${LOG_FILE}" 2>&1

    log_success "OpenClaw services started"

    log_info "Waiting for containers to initialize (10 seconds)..."
    sleep 10
}

# Verify containers
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

# Configure firewall
configure_firewall() {
    if [ "${ENABLE_UFW}" != "true" ]; then
        log_info "Firewall configuration skipped (ENABLE_UFW=false)"
        return 0
    fi

    log_info "Configuring UFW firewall..."

    if sudo ufw status | grep -q "Status: active"; then
        log_info "UFW is already active"
    else
        log_info "Allowing SSH (port 22)..."
        sudo ufw allow 22/tcp >> "${LOG_FILE}" 2>&1

        log_info "Enabling UFW..."
        sudo ufw --force enable >> "${LOG_FILE}" 2>&1
    fi

    log_info "Allowing OpenClaw Gateway (port ${OPENCLAW_GATEWAY_PORT})..."
    if [ "${UFW_ALLOW_FROM}" = "any" ]; then
        sudo ufw allow ${OPENCLAW_GATEWAY_PORT}/tcp >> "${LOG_FILE}" 2>&1
    else
        sudo ufw allow from ${UFW_ALLOW_FROM} to any port ${OPENCLAW_GATEWAY_PORT} proto tcp >> "${LOG_FILE}" 2>&1
    fi

    log_success "Firewall configured successfully"
    log_info "Firewall status:"
    sudo ufw status | tee -a "${LOG_FILE}"
}

#=============================================================================
# SECTION 6: PLUGIN CONFIGURATION FUNCTIONS
#=============================================================================

# Generate gateway token
generate_gateway_token() {
    if [ -z "${OPENCLAW_GATEWAY_TOKEN}" ]; then
        log_info "Generating gateway token..."
        OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
        log_success "Gateway token generated"
    else
        log_info "Using provided gateway token"
    fi
}

# Create auth profiles for multiple providers
create_auth_profiles() {
    log_info "Creating authentication profiles..."

    local auth_file="${OPENCLAW_CONFIG_DIR}/agents/main/agent/auth-profiles.json"
    mkdir -p "$(dirname "${auth_file}")"

    # Build JSON dynamically based on which keys are provided
    local profiles=""

    # Anthropic (always included, required)
    profiles+="  \"anthropic-main\": {
    \"provider\": \"anthropic\",
    \"apiKey\": \"${ANTHROPIC_API_KEY}\",
    \"mode\": \"api_key\"
  }"

    # OpenAI (optional)
    if [ -n "$OPENAI_API_KEY" ]; then
        profiles+=",
  \"openai-main\": {
    \"provider\": \"openai\",
    \"apiKey\": \"${OPENAI_API_KEY}\",
    \"mode\": \"api_key\"
  }"
    fi

    # Gemini (optional)
    if [ -n "$GEMINI_API_KEY" ]; then
        profiles+=",
  \"gemini-main\": {
    \"provider\": \"gemini\",
    \"apiKey\": \"${GEMINI_API_KEY}\",
    \"mode\": \"api_key\"
  }"
    fi

    # Codex (optional, separate profile if key differs from OpenAI)
    if [ -n "$CODEX_API_KEY" ] && [ "$CODEX_API_KEY" != "$OPENAI_API_KEY" ]; then
        profiles+=",
  \"codex-main\": {
    \"provider\": \"openai\",
    \"apiKey\": \"${CODEX_API_KEY}\",
    \"mode\": \"api_key\"
  }"
    fi

    cat > "${auth_file}" <<EOF
{
${profiles}
}
EOF

    chmod 600 "${auth_file}"
    log_success "Authentication profiles created at ${auth_file}"
}

# Create OpenClaw config with multi-provider support
create_openclaw_config() {
    log_info "Creating OpenClaw configuration file..."

    local config_file="${OPENCLAW_CONFIG_DIR}/openclaw.json"

    # Note: workspace path must be the container path (/home/node/.openclaw/workspace)
    # not the host path (${OPENCLAW_WORKSPACE_DIR}) because the config is read inside
    # the Docker container where the volume is mounted at /home/node/.openclaw/workspace

    # Build auth order based on configured providers
    local auth_order=""
    auth_order+="    \"anthropic\": [\"anthropic-main\"]"

    if [ -n "$OPENAI_API_KEY" ]; then
        auth_order+=",
    \"openai\": [\"openai-main\"]"
    fi

    if [ -n "$GEMINI_API_KEY" ]; then
        auth_order+=",
    \"gemini\": [\"gemini-main\"]"
    fi

    # Codex auth order (uses codex-main if separate key, otherwise openai-main)
    if [ -n "$CODEX_API_KEY" ] && [ "$CODEX_API_KEY" != "$OPENAI_API_KEY" ]; then
        # Only add separate entry if not already covered by openai order
        if [ -z "$OPENAI_API_KEY" ]; then
            auth_order+=",
    \"openai\": [\"codex-main\"]"
        fi
    fi

    # Telegram channel configuration
    local telegram_enabled="false"
    if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
        telegram_enabled="true"
    fi

    # Build models allowlist for /model switching (must be a record/object)
    local models_list=""
    models_list+="      \"anthropic/claude-opus-4-6\": {\"alias\": \"opus\"},
      \"anthropic/claude-sonnet-4-5\": {\"alias\": \"sonnet\"}"

    # Build providers section for Codex
    local models_providers=""
    if [ -n "$CODEX_API_KEY" ] || [ "$CODEX_AUTH_METHOD" = "cli_signin" ]; then
        models_list+=",
      \"openai/gpt-5.2-codex\": {\"alias\": \"codex\"}"

        if [ "$CODEX_AUTH_METHOD" = "cli_signin" ]; then
            models_providers=",
  \"models\": {
    \"mode\": \"merge\",
    \"providers\": {
      \"openai-codex\": {
        \"api\": \"openai-chat\",
        \"auth\": \"cli_signin\",
        \"models\": [{\"id\": \"gpt-5.2-codex\", \"name\": \"GPT-5.2 Codex\"}]
      }
    }
  }"
        elif [ -n "$CODEX_API_KEY" ]; then
            models_providers=",
  \"models\": {
    \"mode\": \"merge\",
    \"providers\": {
      \"openai-codex\": {
        \"api\": \"openai-chat\",
        \"apiKey\": \"${CODEX_API_KEY}\",
        \"models\": [{\"id\": \"gpt-5.2-codex\", \"name\": \"GPT-5.2 Codex\"}]
      }
    }
  }"
        fi
    fi

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
      "workspace": "/home/node/.openclaw/workspace",
      "model": {
        "primary": "${BRAIN_MODEL}",
        "fallbacks": ["anthropic/claude-sonnet-4-5"]
      },
      "models": {
${models_list}
      }
    }
  },
  "channels": {
    "telegram": {
      "enabled": ${telegram_enabled},
      "dmPolicy": "pairing",
      "groupPolicy": "disabled"
    }
  },
  "auth": {
    "profiles": {
      "anthropic-main": {
        "provider": "anthropic",
        "mode": "api_key"
      }$([ -n "$OPENAI_API_KEY" ] && echo ",
      \"openai-main\": {
        \"provider\": \"openai\",
        \"mode\": \"api_key\"
      }")$([ -n "$GEMINI_API_KEY" ] && echo ",
      \"gemini-main\": {
        \"provider\": \"gemini\",
        \"mode\": \"api_key\"
      }")$([ -n "$CODEX_API_KEY" ] && echo ",
      \"codex-main\": {
        \"provider\": \"openai\",
        \"mode\": \"api_key\"
      }")
    },
    "order": {
${auth_order}
    }
  }${models_providers}
}
EOF

    chmod 600 "${config_file}"
    log_success "OpenClaw configuration created at ${config_file}"
}

# Create .env file for Docker Compose
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

    # Add optional keys
    if [ -n "$OPENAI_API_KEY" ]; then
        echo "OPENAI_API_KEY=${OPENAI_API_KEY}" >> "${env_file}"
    fi
    if [ -n "$CODEX_API_KEY" ]; then
        echo "CODEX_API_KEY=${CODEX_API_KEY}" >> "${env_file}"
    fi

    chmod 600 "${env_file}"
    log_success ".env file created at ${env_file}"
}

# Fix config permissions
fix_config_permissions() {
    log_info "Setting proper ownership for configuration files..."

    # uid 1000 = node user in Docker container
    sudo chown -R 1000:1000 "${OPENCLAW_CONFIG_DIR}"

    log_success "Configuration file ownership set to uid 1000 (node user)"
}

#=============================================================================
# SECTION 6.5: TELEGRAM PAIRING AUTOMATION FUNCTIONS
#=============================================================================

# Get Telegram bot username via API
get_telegram_bot_username() {
    local bot_token="$1"

    log_info "Fetching bot username from Telegram API..."

    local response
    response=$(curl -s "https://api.telegram.org/bot${bot_token}/getMe" || echo '{"ok":false}')

    local ok
    ok=$(echo "$response" | jq -r '.ok // false' 2>/dev/null || echo "false")

    if [ "$ok" = "true" ]; then
        local username
        username=$(echo "$response" | jq -r '.result.username // "unknown"' 2>/dev/null || echo "unknown")
        echo "$username"
    else
        log_warn "Could not fetch bot username from API"
        echo "your_bot"
    fi
}

# Get pairing data from file (local or remote)
get_pairing_data() {
    local pairing_file="${OPENCLAW_CONFIG_DIR}/credentials/telegram-pairing.json"

    if [ "$EXECUTION_MODE" = "remote" ]; then
        ${SSH_CMD} "${REMOTE_SSH_HOST}" "cat ${pairing_file} 2>/dev/null || echo '{}'"
    else
        cat "$pairing_file" 2>/dev/null || echo "{}"
    fi
}

# Extract latest pairing code from pairing data
extract_latest_pairing_code() {
    local pairing_data="$1"
    echo "$pairing_data" | jq -r '.requests[-1].code // empty' 2>/dev/null || echo ""
}

# Extract latest user ID from pairing data
extract_latest_user_id() {
    local pairing_data="$1"
    echo "$pairing_data" | jq -r '.requests[-1].id // empty' 2>/dev/null || echo ""
}

# Approve Telegram pairing
approve_telegram_pairing() {
    local user_id="$1"
    local pairing_code="$2"
    local pairing_file="${OPENCLAW_CONFIG_DIR}/credentials/telegram-pairing.json"

    log_info "Approving pairing for user ${user_id}..."

    # Read current pairing data
    local pairing_data
    pairing_data=$(get_pairing_data)

    # Find the request to approve
    local request
    request=$(echo "$pairing_data" | jq --arg id "$user_id" --arg code "$pairing_code" \
        '.requests[] | select(.id == $id and .code == $code)' 2>/dev/null || echo "{}")

    if [ "$request" = "{}" ]; then
        log_error "Pairing request not found for user ${user_id}"
        return 1
    fi

    # Add approvedAt timestamp
    local approved_request
    approved_request=$(echo "$request" | jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
        '. + {approvedAt: $now}')

    # Remove from requests and add to approved
    local new_pairing_data
    new_pairing_data=$(echo "$pairing_data" | jq --arg id "$user_id" --arg code "$pairing_code" \
        --argjson approved "$approved_request" \
        '.requests = (.requests | map(select(.id != $id or .code != $code))) |
         .approved = ((.approved // []) + [$approved])')

    # Write new pairing data
    if [ "$EXECUTION_MODE" = "remote" ]; then
        local temp_file="/tmp/telegram-pairing-$$.json"
        echo "$new_pairing_data" | jq '.' > "$temp_file"

        # Copy to remote
        if [ "$REMOTE_SSH_AUTH_METHOD" = "password" ]; then
            sshpass -p "$REMOTE_SSH_PASSWORD" scp -o StrictHostKeyChecking=accept-new \
                "$temp_file" "${REMOTE_SSH_HOST}:${pairing_file}"
        else
            scp -i "${REMOTE_SSH_KEY_PATH}" -o StrictHostKeyChecking=accept-new \
                "$temp_file" "${REMOTE_SSH_HOST}:${pairing_file}"
        fi

        rm -f "$temp_file"

        # Fix permissions
        ${SSH_CMD} "${REMOTE_SSH_HOST}" "chown 1000:1000 ${pairing_file} && chmod 600 ${pairing_file}"

        # Also write user_id to allowFrom file (OpenClaw uses this to gate access)
        local allowfrom_file="${OPENCLAW_CONFIG_DIR}/credentials/telegram-default-allowFrom.json"
        ${SSH_CMD} "${REMOTE_SSH_HOST}" "python3 - <<'PYEOF'
import json, os
f = '${allowfrom_file}'
d = json.load(open(f)) if os.path.exists(f) else {'version': 1, 'allowFrom': []}
if '${user_id}' not in d.get('allowFrom', []):
    d.setdefault('allowFrom', []).append('${user_id}')
json.dump(d, open(f, 'w'), indent=2)
os.chmod(f, 0o600)
import shutil; shutil.chown(f, 1000, 1000)
print('allowFrom updated')
PYEOF"
    else
        echo "$new_pairing_data" | jq '.' | sudo tee "$pairing_file" > /dev/null
        sudo chown 1000:1000 "$pairing_file"
        sudo chmod 600 "$pairing_file"

        # Also write user_id to allowFrom file (OpenClaw uses this to gate access)
        local allowfrom_file="${OPENCLAW_CONFIG_DIR}/credentials/telegram-default-allowFrom.json"
        python3 - <<PYEOF
import json, os
f = '${allowfrom_file}'
d = json.load(open(f)) if os.path.exists(f) else {'version': 1, 'allowFrom': []}
if '${user_id}' not in d.get('allowFrom', []):
    d.setdefault('allowFrom', []).append('${user_id}')
json.dump(d, open(f, 'w'), indent=2)
PYEOF
        sudo chown 1000:1000 "$allowfrom_file"
        sudo chmod 600 "$allowfrom_file"
    fi

    log_success "Pairing approved successfully"
}

# Restart gateway to pick up pairing changes
restart_gateway_for_pairing() {
    log_info "Restarting gateway to apply pairing changes..."

    if [ "$EXECUTION_MODE" = "remote" ]; then
        ${SSH_CMD} "${REMOTE_SSH_HOST}" "cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose restart openclaw-gateway"
    else
        cd "${OPENCLAW_INSTALL_DIR}/openclaw" && \
        $(get_docker_cmd) compose restart openclaw-gateway
    fi

    sleep 3  # Give gateway time to start
    log_success "Gateway restarted"
}

# Main Telegram pairing workflow
telegram_pairing_workflow() {
    # Skip if Telegram not enabled
    if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        return 0
    fi

    log_section "Phase 9.5: Telegram Pairing Setup"

    # Get bot username
    local bot_username
    bot_username=$(get_telegram_bot_username "$TELEGRAM_BOT_TOKEN")

    # Check if user wants to set up pairing now
    if [ "$TELEGRAM_AUTO_PAIRING" = "prompt" ]; then
        echo ""
        log_info "Telegram bot configured: @${bot_username}"
        echo ""
        read -p "Would you like to set up Telegram pairing now? (Y/n): " response
        if [[ "$response" =~ ^[Nn] ]]; then
            log_info "Skipping pairing - can be done later via: ./scripts/telegram-pairing-helper.sh"
            return 0
        fi
    elif [ "$TELEGRAM_AUTO_PAIRING" = "no" ]; then
        log_info "Auto-pairing disabled - set up later via: ./scripts/telegram-pairing-helper.sh"
        return 0
    fi

    # Interactive pairing flow
    echo ""
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║  Please send a message to @${bot_username} on Telegram    "
    log_info "║  (Open Telegram and search for: @${bot_username})         "
    log_info "╚════════════════════════════════════════════════════════════╝"
    echo ""
    read -p "Press Enter after sending a message to the bot..."

    # Wait for pairing request (60s timeout)
    log_info "Waiting for pairing request..."
    local pairing_code=""
    local user_id=""

    for i in $(seq 1 60); do
        local pairing_data
        pairing_data=$(get_pairing_data)
        pairing_code=$(extract_latest_pairing_code "$pairing_data")
        user_id=$(extract_latest_user_id "$pairing_data")

        if [ -n "$pairing_code" ] && [ -n "$user_id" ]; then
            log_success "Found pairing request!"
            echo "  User ID: ${user_id}"
            echo "  Code: ${pairing_code}"
            break
        fi

        if [ $((i % 10)) -eq 0 ]; then
            log_info "Still waiting... (${i}s elapsed)"
        fi
        sleep 1
    done

    if [ -z "$pairing_code" ] || [ -z "$user_id" ]; then
        log_warn "No pairing request detected within 60 seconds"
        log_info "You can complete pairing later by running:"
        log_info "  ./scripts/telegram-pairing-helper.sh"
        return 1
    fi

    # Auto-approve
    log_info "Auto-approving pairing..."
    approve_telegram_pairing "$user_id" "$pairing_code" || {
        log_error "Failed to approve pairing"
        return 1
    }

    restart_gateway_for_pairing || {
        log_error "Failed to restart gateway"
        return 1
    }

    echo ""
    log_success "═══════════════════════════════════════════════════════════"
    log_success "  Telegram pairing completed successfully!"
    log_success "  Send another message to @${bot_username} to test"
    log_success "═══════════════════════════════════════════════════════════"
    echo ""
}

#=============================================================================
# SECTION 7: TROUBLESHOOTING FUNCTIONS
#=============================================================================

# Check Telegram plugin enabled
check_telegram_enabled() {
    local config_file="${OPENCLAW_CONFIG_DIR}/openclaw.json"

    if [ ! -f "$config_file" ]; then
        echo "false"
        return 1
    fi

    local enabled=$(python3 -c "
import sys, json
try:
    with open('${config_file}', 'r') as f:
        config = json.load(f)
    print(config.get('channels', {}).get('telegram', {}).get('enabled', False))
except:
    print('false')
" 2>/dev/null || echo "false")

    echo "$enabled"
    [ "$enabled" = "True" ] && return 0 || return 1
}

# Check Docker container status
check_container_status() {
    local docker_cmd=$(get_docker_cmd)

    cd "${OPENCLAW_INSTALL_DIR}/openclaw" 2>/dev/null || return 1

    local status=$(${docker_cmd} compose ps openclaw-gateway --format '{{.Status}}' 2>/dev/null || echo "not_running")

    if echo "$status" | grep -q "Up"; then
        return 0
    else
        return 1
    fi
}

# Diagnose and fix issues
diagnose_and_fix() {
    log_section "Running Diagnostics"

    local issues_found=0
    local warnings_found=0

    # Check 1: Telegram enabled
    log_info "[1/9] Checking Telegram plugin status..."
    if check_telegram_enabled >/dev/null 2>&1; then
        log_success "Telegram plugin is enabled"
    else
        log_warn "Telegram plugin is disabled or not configured"
        warnings_found=$((warnings_found + 1))
    fi

    # Check 2: Container status
    log_info "[2/9] Checking Docker container status..."
    if check_container_status; then
        log_success "Gateway container is running"
    else
        log_error "Gateway container is not running"
        issues_found=$((issues_found + 1))
    fi

    # Check 3: Gateway accessibility
    log_info "[3/9] Checking gateway accessibility..."
    local http_code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${OPENCLAW_GATEWAY_PORT}/" 2>/dev/null || echo "000")
    if [ "$http_code" = "401" ] || [ "$http_code" = "200" ]; then
        log_success "Gateway is accessible (HTTP ${http_code})"
    else
        log_error "Gateway is not accessible (HTTP ${http_code})"
        issues_found=$((issues_found + 1))
    fi

    # Check 4: Config files valid
    log_info "[4/9] Validating configuration files..."
    local config_file="${OPENCLAW_CONFIG_DIR}/openclaw.json"
    if [ -f "$config_file" ] && python3 -m json.tool "$config_file" > /dev/null 2>&1; then
        log_success "Configuration file is valid JSON"

        # Check workspace path is correct (container path, not host path)
        local workspace_path=$(python3 -c "
import json
try:
    with open('${config_file}', 'r') as f:
        config = json.load(f)
        print(config.get('agents', {}).get('defaults', {}).get('workspace', ''))
except:
    pass
" 2>/dev/null || echo "")

        if [ "$workspace_path" != "/home/node/.openclaw/workspace" ]; then
            log_warn "Workspace path is incorrect: ${workspace_path}"
            log_info "Expected: /home/node/.openclaw/workspace (container path)"
            log_info "Fix: Update ${config_file} and restart gateway"
            warnings_found=$((warnings_found + 1))
        fi
    else
        log_error "Configuration file is missing or invalid"
        issues_found=$((issues_found + 1))
    fi

    # Check 5: Workspace permissions
    log_info "[5/9] Checking workspace permissions..."
    if [ -d "${OPENCLAW_WORKSPACE_DIR}" ]; then
        local owner=$(stat -c '%u' "${OPENCLAW_WORKSPACE_DIR}")
        if [ "$owner" = "1000" ]; then
            log_success "Workspace has correct permissions (uid 1000)"
        else
            log_warn "Workspace has incorrect permissions (uid ${owner}), should be 1000"
            warnings_found=$((warnings_found + 1))
        fi
    else
        log_warn "Workspace directory does not exist"
        warnings_found=$((warnings_found + 1))
    fi

    # Check 6: Telegram API connectivity
    log_info "[6/9] Checking Telegram API connectivity..."
    local telegram_api_code=$(curl -s -o /dev/null -w '%{http_code}' "https://api.telegram.org" 2>/dev/null || echo "000")
    if [ "$telegram_api_code" = "404" ] || [ "$telegram_api_code" = "200" ] || [ "$telegram_api_code" = "302" ]; then
        if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
            # Test with actual bot token if available
            local bot_response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" 2>/dev/null || echo "")
            local bot_ok=$(echo "$bot_response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('ok', False))" 2>/dev/null || echo "False")
            if [ "$bot_ok" = "True" ]; then
                local bot_username=$(echo "$bot_response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', {}).get('username', ''))" 2>/dev/null || echo "")
                log_success "Telegram API accessible (@${bot_username})"
            else
                log_warn "Telegram API reachable but bot token may be invalid"
                warnings_found=$((warnings_found + 1))
            fi
        else
            log_success "Telegram API reachable (HTTP ${telegram_api_code})"
        fi
    else
        log_error "Cannot reach Telegram API (HTTP ${telegram_api_code})"
        issues_found=$((issues_found + 1))
    fi

    # Check 7: Gateway logs analysis
    log_info "[7/9] Analyzing gateway logs for errors..."
    if check_container_status >/dev/null 2>&1; then
        local critical_errors=$(cd "${OPENCLAW_INSTALL_DIR}" && docker compose logs openclaw-gateway --tail=100 2>/dev/null | grep -iE "ERROR|FATAL|Connection refused" | wc -l || echo "0")
        if [ "$critical_errors" -eq 0 ]; then
            log_success "No critical errors in gateway logs"
        else
            log_warn "Found ${critical_errors} error message(s) in gateway logs"
            log_info "Review with: cd ${OPENCLAW_INSTALL_DIR} && docker compose logs openclaw-gateway"
            warnings_found=$((warnings_found + 1))
        fi
    else
        log_warn "Cannot check logs - gateway not running"
    fi

    # Check 8: Telegram pairing status
    log_info "[8/9] Checking Telegram pairing status..."
    local pairing_file="${OPENCLAW_CONFIG_DIR}/credentials/telegram-pairing.json"
    if [ -f "$pairing_file" ]; then
        local pairing_stats=$(python3 -c "
import json
try:
    with open('${pairing_file}', 'r') as f:
        data = json.load(f)
        pending = len(data.get('requests', []))
        approved = len(data.get('approved', []))
        print(f'{pending},{approved}')
except:
    print('0,0')
" 2>/dev/null || echo "0,0")
        local pending=$(echo "$pairing_stats" | cut -d',' -f1)
        local approved=$(echo "$pairing_stats" | cut -d',' -f2)

        if [ "$pending" -gt 0 ]; then
            log_warn "${pending} pending pairing request(s), ${approved} approved user(s)"
            log_info "Approve via dashboard or run: ./scripts/fix-telegram-pairing.sh"
            warnings_found=$((warnings_found + 1))
        else
            log_success "Pairing status: ${approved} approved user(s), ${pending} pending"
        fi
    else
        log_warn "Pairing file does not exist yet"
    fi

    # Check 9: Docker image integrity
    log_info "[9/9] Checking Docker image integrity..."
    local openclaw_image=$(docker images openclaw:local --format "{{.ID}}" 2>/dev/null || echo "")
    if [ -n "$openclaw_image" ]; then
        local corrupted_images=$(docker images --filter "dangling=true" -q 2>/dev/null | wc -l || echo "0")
        local image_size=$(docker images openclaw:local --format "{{.Size}}" 2>/dev/null || echo "unknown")
        if [ "$corrupted_images" -eq 0 ]; then
            log_success "Docker image 'openclaw:local' exists (${image_size})"
        else
            log_warn "Found ${corrupted_images} dangling Docker image(s) - consider cleanup"
            log_info "Cleanup with: docker image prune"
            warnings_found=$((warnings_found + 1))
        fi
    else
        log_error "Docker image 'openclaw:local' not found"
        issues_found=$((issues_found + 1))
    fi

    log_section "Diagnostic Summary"

    if [ $issues_found -eq 0 ] && [ $warnings_found -eq 0 ]; then
        log_success "All checks passed!"
        return 0
    elif [ $issues_found -eq 0 ]; then
        log_warn "${warnings_found} warning(s) found, but no critical issues"
        return 0
    else
        log_error "Found ${issues_found} critical issue(s) and ${warnings_found} warning(s)"
        return 1
    fi
}

#=============================================================================
# SECTION 8: REMOTE EXECUTION FUNCTIONS
#=============================================================================

# Global SSH command variables (set by setup_ssh_authentication)
SSH_CMD=""
SCP_CMD=""

# Setup SSH authentication
setup_ssh_authentication() {
    log_info "Setting up SSH authentication..."

    if [ "$REMOTE_SSH_AUTH_METHOD" = "password" ]; then
        # Check if sshpass is installed
        if ! command -v sshpass &> /dev/null; then
            log_info "Installing sshpass..."
            sudo apt-get update >> "${EXTENDED_LOG_FILE}" 2>&1
            sudo apt-get install -y sshpass >> "${EXTENDED_LOG_FILE}" 2>&1
        fi

        # Export password as environment variable for sshpass (more secure and handles special chars)
        export SSHPASS="${REMOTE_SSH_PASSWORD}"

        # Use -e flag to read password from SSHPASS environment variable
        SSH_CMD="sshpass -e ssh -o StrictHostKeyChecking=accept-new"
        SCP_CMD="sshpass -e scp -o StrictHostKeyChecking=accept-new"

        log_success "SSH authentication configured (password mode)"
    else
        # SSH key mode
        SSH_CMD="ssh -i '${REMOTE_SSH_KEY_PATH}' -o StrictHostKeyChecking=accept-new"
        SCP_CMD="scp -i '${REMOTE_SSH_KEY_PATH}' -o StrictHostKeyChecking=accept-new"

        log_success "SSH authentication configured (key mode)"
    fi
}

# Test SSH connection
test_ssh_connection() {
    log_info "Testing SSH connection to ${REMOTE_SSH_HOST}..."

    if ${SSH_CMD} "${REMOTE_SSH_HOST}" "echo 'SSH connection successful'" >> "${LOG_FILE}" 2>&1; then
        log_success "SSH connection test passed"
        return 0
    else
        log_error "SSH connection test failed"
        return 1
    fi
}

# Verify remote server
verify_remote_server() {
    log_info "Verifying remote server..."

    # Check OS
    log_info "Checking OS version..."
    ${SSH_CMD} "${REMOTE_SSH_HOST}" "cat /etc/os-release | grep -E '^(NAME|VERSION)='" | tee -a "${LOG_FILE}"

    # Check disk space
    log_info "Checking disk space (need >10GB)..."
    ${SSH_CMD} "${REMOTE_SSH_HOST}" "df -h / | tail -1" | tee -a "${LOG_FILE}"

    # Check memory
    log_info "Checking memory (need >2GB)..."
    ${SSH_CMD} "${REMOTE_SSH_HOST}" "free -h | grep Mem" | tee -a "${LOG_FILE}"

    # Test network
    log_info "Testing network connectivity..."
    ${SSH_CMD} "${REMOTE_SSH_HOST}" "ping -c 2 github.com > /dev/null 2>&1 && echo 'GitHub: Reachable' || echo 'GitHub: Unreachable'" | tee -a "${LOG_FILE}"

    log_success "Remote server verification complete"
}

# Transfer files to remote
transfer_files_to_remote() {
    log_info "Transferring installation files to remote server..."

    local remote_dir="/tmp/openclaw-installer-$$"

    # Create remote directory
    ${SSH_CMD} "${REMOTE_SSH_HOST}" "mkdir -p ${remote_dir}"

    # Transfer this script
    log_info "Transferring unified installation script..."
    ${SCP_CMD} "$0" "${REMOTE_SSH_HOST}:${remote_dir}/unified-install-openclaw.sh"

    # Create .env file for remote
    local temp_env="/tmp/openclaw-remote-env-$$"
    cat > "${temp_env}" <<EOF
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
OPENAI_API_KEY=${OPENAI_API_KEY}
GEMINI_API_KEY=${GEMINI_API_KEY}
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
PRESERVE_WORKSPACE=${PRESERVE_WORKSPACE}
EOF

    # Transfer .env
    log_info "Transferring environment configuration..."
    ${SCP_CMD} "${temp_env}" "${REMOTE_SSH_HOST}:${remote_dir}/.env"
    rm -f "${temp_env}"

    log_success "Files transferred to: ${remote_dir}"

    echo "${remote_dir}"
}

# Execute installation on remote
execute_remote_installation() {
    local remote_dir="$1"

    log_info "Executing installation on remote server..."

    # Execute installation - use set -a to auto-export all variables from .env
    ${SSH_CMD} "${REMOTE_SSH_HOST}" "cd '${remote_dir}' && set -a && source .env && set +a && chmod +x unified-install-openclaw.sh && ./unified-install-openclaw.sh --mode local" 2>&1 | tee -a "${LOG_FILE}"

    local exit_code=${PIPESTATUS[0]}

    if [ $exit_code -eq 0 ]; then
        log_success "Remote installation completed successfully"
        return 0
    else
        log_error "Remote installation failed with exit code: ${exit_code}"
        return 1
    fi
}

# Fetch logs from remote
fetch_remote_logs() {
    local remote_log_dir="/root/openclaw-install-logs"

    log_info "Fetching logs from remote server..."

    mkdir -p "${LOG_DIR}/remote-logs"

    ${SCP_CMD} -r "${REMOTE_SSH_HOST}:${remote_log_dir}/*" "${LOG_DIR}/remote-logs/" 2>/dev/null || log_warn "Could not fetch remote logs"

    log_info "Remote logs saved to: ${LOG_DIR}/remote-logs/"
}

# Main remote installation flow
main_remote_installation() {
    log_section "Remote Installation Mode"

    # Step 1: Setup SSH
    setup_ssh_authentication

    # Step 2: Test connection
    test_ssh_connection || exit 1

    # Step 3: Verify server
    verify_remote_server

    # Step 4: Transfer files
    # Capture only the last line (the directory path), not the log output
    remote_dir=$(transfer_files_to_remote | tail -1)

    # Step 5: Execute installation
    execute_remote_installation "$remote_dir" || exit 1

    # Step 6: Fetch logs
    fetch_remote_logs

    # Step 6.5: Telegram Pairing Setup (optional)
    if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
        telegram_pairing_workflow || log_warn "Pairing can be completed later via: ./scripts/telegram-pairing-helper.sh"
    fi

    # Step 7: Display completion
    display_remote_completion_message
}

#=============================================================================
# SECTION 9: VERIFICATION FUNCTIONS
#=============================================================================

# Verify installation
verify_installation() {
    log_info "Verifying installation..."

    cd "${OPENCLAW_INSTALL_DIR}/openclaw"

    local docker_cmd=$(get_docker_cmd)

    log_info "Waiting for gateway to become ready (up to 60 seconds)..."
    local retries=0
    while [ $retries -lt ${HEALTH_CHECK_RETRIES} ]; do
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${OPENCLAW_GATEWAY_PORT}/" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ] || [ "$http_code" = "401" ]; then
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
# SECTION 10: MAIN EXECUTION FLOW
#=============================================================================

# Display completion message for local installation
display_completion_message() {
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

    log_section "OpenClaw Installation Complete!"

    # Build configured providers list
    local providers=""
    providers="  ✓ Anthropic (Claude Sonnet 4.5)"
    [ -n "$OPENAI_API_KEY" ] && providers+=$'\n'"  ✓ OpenAI (ChatGPT, GPT-4)"
    [ -n "$GEMINI_API_KEY" ] && providers+=$'\n'"  ✓ Google Gemini"
    ([ -n "$CODEX_API_KEY" ] || [ "$CODEX_AUTH_METHOD" = "cli_signin" ]) && providers+=$'\n'"  ✓ OpenAI Codex (GPT-5.2 Codex)"

    # Brain/Hands model info
    local model_info=""
    model_info="  Brain (planning/reasoning): ${BRAIN_MODEL}"
    model_info+=$'\n'"  Fallback: anthropic/claude-sonnet-4-5"
    if [ -n "$CODEX_API_KEY" ] || [ "$CODEX_AUTH_METHOD" = "cli_signin" ]; then
        model_info+=$'\n'"  Hands/Coding: openai/gpt-5.2-codex (switch via /model codex)"
    fi
    local model_aliases="opus, sonnet"
    ([ -n "$CODEX_API_KEY" ] || [ "$CODEX_AUTH_METHOD" = "cli_signin" ]) && model_aliases+=", codex"
    model_info+=$'\n'"  Switch models: Use /model <alias> in chat (${model_aliases})"

    # Build enabled channels list
    local channels=""
    [ -n "$TELEGRAM_BOT_TOKEN" ] && channels="  ✓ Telegram"
    [ -z "$channels" ] && channels="  (No channels configured)"

    cat <<EOF | tee -a "${LOG_FILE}"

Access Information:
  Dashboard: http://${server_ip}:${OPENCLAW_GATEWAY_PORT}
  Gateway Token: ${OPENCLAW_GATEWAY_TOKEN}

Configured Providers:
${providers}
Model Architecture:
${model_info}
Enabled Channels:
${channels}
Workspace Location: ${OPENCLAW_WORKSPACE_DIR}
Memory Preserved: $([ "$PRESERVE_WORKSPACE" = "yes" ] && echo "Yes" || echo "No")

Next Steps:
  1. Access dashboard at http://${server_ip}:${OPENCLAW_GATEWAY_PORT}
  2. Use token: ${OPENCLAW_GATEWAY_TOKEN}
$([ -n "$TELEGRAM_BOT_TOKEN" ] && echo "  3. For Telegram pairing:")
$([ -n "$TELEGRAM_BOT_TOKEN" ] && echo "     - If not done during install, run: ./scripts/telegram-pairing-helper.sh")
$([ -n "$TELEGRAM_BOT_TOKEN" ] && echo "     - Or approve manually in dashboard after sending a message to bot")
$([ "$CODEX_AUTH_METHOD" = "cli_signin" ] && echo "  NOTE: Run 'codex auth' inside the container to complete Codex CLI sign-in")

Container Management:
  Start:   cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose up -d
  Stop:    cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose down
  Logs:    cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose logs -f openclaw-gateway
  Status:  cd ${OPENCLAW_INSTALL_DIR}/openclaw && docker compose ps

Configuration Files:
  Main config:    ${OPENCLAW_CONFIG_DIR}/openclaw.json
  Auth profiles:  ${OPENCLAW_CONFIG_DIR}/agents/main/agent/auth-profiles.json
  Environment:    ${OPENCLAW_INSTALL_DIR}/openclaw/.env
  Workspace:      ${OPENCLAW_WORKSPACE_DIR}

Troubleshooting:
  Run diagnostics: $0 --diagnose

================================================================================

EOF
}

# Display completion message for remote installation
display_remote_completion_message() {
    local server_ip=$(echo "$REMOTE_SSH_HOST" | cut -d'@' -f2)

    log_section "Remote OpenClaw Installation Complete!"

    cat <<EOF | tee -a "${LOG_FILE}"

Remote Server: ${REMOTE_SSH_HOST}

Access Information:
  Dashboard: http://${server_ip}:${OPENCLAW_GATEWAY_PORT}
  Gateway Token: ${OPENCLAW_GATEWAY_TOKEN}

Next Steps:
  1. Access dashboard at http://${server_ip}:${OPENCLAW_GATEWAY_PORT}
  2. Use token: ${OPENCLAW_GATEWAY_TOKEN}
$([ -n "$TELEGRAM_BOT_TOKEN" ] && echo "  3. For Telegram: Send /start to your bot and approve pairing in dashboard")

Remote Management:
  SSH to server: ssh ${REMOTE_SSH_HOST}
  Check logs:    ${SSH_CMD} ${REMOTE_SSH_HOST} "cd ~/openclaw/openclaw && docker compose logs -f"

================================================================================

EOF
}

# Interactive prompts for missing variables
prompt_for_missing_variables() {
    log_section "Configuration Setup"

    # Execution mode
    if [ -z "$EXECUTION_MODE" ] || [ "$EXECUTION_MODE" = "local" ]; then
        echo "Execution Mode: Local (install on this machine)"
        echo "  To install on a remote server, use: --mode remote"
        echo ""
    fi

    # Anthropic API key (required)
    if [ -z "$ANTHROPIC_API_KEY" ]; then
        echo "Anthropic API key is required."
        echo "Get your key from: https://console.anthropic.com/"
        ANTHROPIC_API_KEY=$(prompt_with_default "Enter Anthropic API key" "")

        while [ -z "$ANTHROPIC_API_KEY" ]; do
            log_error "Anthropic API key is required"
            ANTHROPIC_API_KEY=$(prompt_with_default "Enter Anthropic API key" "")
        done
    fi

    # Optional providers
    echo ""
    echo "Optional: Additional AI Providers"
    echo "  Press Enter to skip any provider you don't want to configure"
    echo ""

    if [ -z "$OPENAI_API_KEY" ]; then
        OPENAI_API_KEY=$(prompt_with_default "OpenAI API key (optional)" "")
    fi

    if [ -z "$GEMINI_API_KEY" ]; then
        GEMINI_API_KEY=$(prompt_with_default "Google Gemini API key (optional)" "")
    fi

    # Codex configuration
    if [ -z "$CODEX_API_KEY" ] && [ -z "$CODEX_AUTH_METHOD" ]; then
        echo ""
        echo "Optional: OpenAI Codex (coding model)"
        echo "  Options: api_key, cli_signin, or press Enter to skip"
        echo ""
        CODEX_AUTH_METHOD=$(prompt_with_default "Codex auth method (api_key/cli_signin/skip)" "")
        if [ "$CODEX_AUTH_METHOD" = "api_key" ]; then
            if [ -n "$OPENAI_API_KEY" ]; then
                echo "  Reuse OpenAI key for Codex? (press Enter to reuse, or enter a different key)"
                local codex_key_input
                codex_key_input=$(prompt_with_default "Codex API key" "${OPENAI_API_KEY}")
                CODEX_API_KEY="${codex_key_input}"
            else
                CODEX_API_KEY=$(prompt_with_default "Codex API key" "")
            fi
        elif [ "$CODEX_AUTH_METHOD" = "skip" ] || [ -z "$CODEX_AUTH_METHOD" ]; then
            CODEX_AUTH_METHOD=""
        fi
    fi

    # Brain model preference
    if [ "$BRAIN_MODEL" = "anthropic/claude-opus-4-6" ]; then
        echo ""
        echo "Brain Model Configuration"
        echo "  The brain model handles planning and reasoning."
        echo "  Default: anthropic/claude-opus-4-6"
        echo "  Press Enter to keep default."
        echo ""
        BRAIN_MODEL=$(prompt_with_default "Brain model (provider/model)" "anthropic/claude-opus-4-6")
    fi

    # Telegram
    echo ""
    echo "Optional: Telegram Integration"
    echo "  Get a bot token from @BotFather on Telegram"
    echo "  Press Enter to skip if you don't want Telegram integration"
    echo ""

    if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        TELEGRAM_BOT_TOKEN=$(prompt_with_default "Telegram bot token (optional)" "")
    fi

    # Remote mode prompts
    if [ "$EXECUTION_MODE" = "remote" ]; then
        echo ""
        echo "Remote Installation Configuration"
        echo ""

        if [ -z "$REMOTE_SSH_HOST" ]; then
            REMOTE_SSH_HOST=$(prompt_with_default "SSH host (user@hostname)" "")
        fi

        if [ -z "$REMOTE_SSH_AUTH_METHOD" ]; then
            REMOTE_SSH_AUTH_METHOD=$(prompt_with_default "SSH auth method (password/key)" "key")
        fi

        if [ "$REMOTE_SSH_AUTH_METHOD" = "password" ] && [ -z "$REMOTE_SSH_PASSWORD" ]; then
            REMOTE_SSH_PASSWORD=$(prompt_password "SSH password")
        fi

        if [ "$REMOTE_SSH_AUTH_METHOD" = "key" ] && [ -z "$REMOTE_SSH_KEY_PATH" ]; then
            REMOTE_SSH_KEY_PATH=$(prompt_with_default "SSH key path" "${HOME}/.ssh/id_rsa")
        fi
    fi

    log_success "Configuration complete"
}

# Main local installation flow
main_local_installation() {
    log_section "OpenClaw Installation Script v${SCRIPT_VERSION}"
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

    # Phase 8: Restore workspace if needed
    if [ "$PRESERVE_WORKSPACE" = "yes" ]; then
        log_section "Phase 8: Workspace Restoration"
        restore_workspace
    fi

    # Phase 9: Troubleshooting (optional)
    if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
        log_section "Phase 9: Post-Installation Diagnostics"
        diagnose_and_fix || log_warn "Some diagnostic checks failed, but installation completed"
    fi

    # Phase 9.5: Telegram Pairing Setup (optional)
    if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
        telegram_pairing_workflow || log_warn "Pairing can be completed later via: ./scripts/telegram-pairing-helper.sh"
    fi

    # Phase 10: Completion
    display_completion_message

    log_success "Installation completed successfully!"
}

# Main entry point
main() {
    # Parse command-line arguments
    parse_arguments "$@"

    # Handle diagnostic mode
    if [ "$DIAGNOSTIC_MODE" = true ]; then
        diagnose_and_fix
        exit $?
    fi

    # Prompt for missing variables if in interactive mode
    if [ -t 0 ]; then  # Check if stdin is a terminal
        prompt_for_missing_variables
    fi

    # Route to appropriate installation mode
    if [ "$EXECUTION_MODE" = "remote" ]; then
        main_remote_installation
    else
        main_local_installation
    fi
}

# Run main
main "$@"
