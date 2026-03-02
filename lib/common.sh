#!/bin/bash
# Shared utilities for ROCm WSL AI Toolkit installer scripts
set -o pipefail

# --- Color Definitions ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# --- Logging & UI Helpers ---
log()     { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $*" >&2; }
headline(){ echo -e "\n${BOLD}${MAGENTA}==== $* ====${NC}" >&2; }

# --- Interaction Helpers ---
confirm(){
    local msg="$1"
    read -p "${msg} (y/N): " -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# --- Environment Checks ---
is_wsl(){
    grep -qi "microsoft" /proc/version 2>/dev/null || grep -qi "microsoft" /proc/sys/kernel/osrelease 2>/dev/null
}

require_wsl(){
    if ! is_wsl; then
        err "This toolkit is designed specifically for Windows Subsystem for Linux (WSL2)."
        err "For native Linux, please use the official AMD ROCm documentation."
        exit 1
    fi
}

has_rocm(){
    command -v rocminfo >/dev/null 2>&1
}

check_not_root(){
    if [ "$EUID" -eq 0 ]; then
        warn "Running as root/sudo is not recommended for this toolkit."
        warn "Please run as a regular user; sudo will be requested only when needed."
        if ! confirm "Do you want to continue anyway?"; then
            exit 1
        fi
    fi
}

# --- Virtual Environment Helpers ---
ensure_venv(){
    local venv_name="$1"
    local venv_path="$HOME/$venv_name"
    if [ ! -f "$venv_path/bin/activate" ]; then
        err "Python virtual environment not found: $venv_path"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$venv_path/bin/activate"
    local py_ver
    py_ver=$(python3 --version 2>&1 | awk '{print $2}')
    success "Activated venv '$venv_name' (Python $py_ver)"
}

# --- Repository & Package Management ---
git_clone_or_update(){
    local url="$1"
    local dir="$2"
    if [ ! -d "$dir/.git" ]; then
        log "Cloning repository from $url..."
        git clone --depth=1 "$url" "$dir" || { err "Failed to clone $url"; return 1; }
    else
        log "Updating existing repository in $dir..."
        git -C "$dir" pull --rebase --autostash || warn "Git update encountered minor issues (continuing...)"
    fi
}

pip_install_if_exists(){
    local req_file="$1"
    if [ ! -f "$req_file" ]; then
        warn "No requirements file found: $req_file"
        return 0
    fi
    log "Installing Python requirements from $(basename "$req_file")..."
    pip install --no-cache-dir -r "$req_file" || { err "Failed to install requirements"; return 1; }
}

ensure_apt_packages(){
    [ $# -eq 0 ] && return 0
    log "Ensuring system packages are installed: $*"
    sudo apt update -y >/dev/null 2>&1
    sudo apt install -y "$@" || { err "Failed to install system packages"; return 1; }
}

# --- Script Header ---
standard_header(){
    headline "$1"
    if is_wsl; then
        log "Environment: Windows Subsystem for Linux (WSL2)"
    else
        warn "Environment: Native Linux (UNSUPPORTED)"
    fi
    
    if has_rocm; then
        log "ROCm Status: Detected"
    else
        warn "ROCm Status: NOT detected (Installation required)"
    fi
}

# Export functions for subshells
export -f log warn err success headline confirm is_wsl require_wsl has_rocm check_not_root ensure_venv git_clone_or_update pip_install_if_exists ensure_apt_packages standard_header

# --- Automatic GPU Environment Detection ---
# This ensures that any script sourcing common.sh immediately has access to 
# the correct GPU environment variables (HSA_OVERRIDE_GFX_VERSION, etc.)
if [ -f "$(dirname "${BASH_SOURCE[0]}")/../scripts/utils/gpu_config.sh" ]; then
    # shellcheck disable=SC1091
    source "$(dirname "${BASH_SOURCE[0]}")/../scripts/utils/gpu_config.sh"
    # Redirect to stderr to keep stdout clean for scripts that capture output
    detect_and_export_rocm_env >&2 || warn "GPU auto-detection encountered an issue"
fi
