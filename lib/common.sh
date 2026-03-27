#!/bin/bash
# Shared utilities for ROCm WSL AI Toolkit installer scripts
set -o pipefail

# --- Color Definitions ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# --- Logging & UI Helpers ---
# --- Logging & UI Helpers ---
log()     { if command -v gum >/dev/null 2>&1; then gum style --foreground 117 "ℹ  $*" >&2; else echo -e "${BLUE}[INFO]${NC} $*" >&2; fi; }
warn()    { if command -v gum >/dev/null 2>&1; then gum style --foreground 214 "⚠  $*" >&2; else echo -e "${YELLOW}[WARN]${NC} $*" >&2; fi; }
err()     { if command -v gum >/dev/null 2>&1; then gum style --foreground 196 "✖  $*" >&2; else echo -e "${RED}[ERROR]${NC} $*" >&2; fi; }
success() { if command -v gum >/dev/null 2>&1; then gum style --foreground 46 "✔  $*" >&2; else echo -e "${GREEN}[OK]${NC} $*" >&2; fi; }
headline(){ if command -v gum >/dev/null 2>&1; then echo ""; gum style --bold --foreground 212 --border normal --border-foreground 212 --padding "0 2" "$*" >&2; else echo -e "\n${BOLD}${MAGENTA}==== $* ====${NC}" >&2; fi; }

# --- Interaction Helpers ---
confirm(){
    local msg="$1"
    if command -v gum >/dev/null 2>&1; then
        gum confirm "$msg" --default=false
    else
        read -p "${msg} (y/N): " -r response
        [[ "$response" =~ ^[Yy]$ ]]
    fi
}

msgbox() {
    local title="$1"
    local text="$2"
    echo ""
    if command -v gum >/dev/null 2>&1; then
        echo -e "$(gum style --bold --foreground 212 "$title")\n\n$text" | gum style --border rounded --margin "0 2" --padding "1 2" --border-foreground 212
    else
        echo -e "\n==== $title ====\n$text"
    fi
    echo ""
    read -rp "  Press Enter to continue..."
}

yesno() {
    local title="$1"
    local text="$2"
    echo ""
    if command -v gum >/dev/null 2>&1; then
        echo -e "$(gum style --bold --foreground 214 "$title")\n\n$text" | gum style --border normal --margin "0 2" --padding "1 2" --border-foreground 214
        echo ""
        gum confirm "Continue?" --default=false
    else
        echo -e "\n==== $title ====\n$text"
        confirm "Continue?"
    fi
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

has_rocdxg(){
    [ -f "/opt/rocm/lib/librocdxg.so" ]
}

has_windows_sdk(){
    local win_kits_base="/mnt/c/Program Files (x86)/Windows Kits/10/Include"
    if [ -d "$win_kits_base" ]; then
        local sdk_version
        sdk_version=$(ls -1 "$win_kits_base" 2>/dev/null | grep -E '^10\.' | sort -V | tail -1)
        if [ -n "$sdk_version" ]; then
            return 0
        fi
    fi
    return 1
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
export -f log warn err success headline confirm msgbox yesno is_wsl require_wsl has_rocm has_rocdxg has_windows_sdk check_not_root ensure_venv git_clone_or_update pip_install_if_exists ensure_apt_packages standard_header

# --- Automatic GPU Environment Detection ---
# This ensures that any script sourcing common.sh immediately has access to 
# the correct GPU environment variables (HSA_OVERRIDE_GFX_VERSION, etc.)
if [ -f "$(dirname "${BASH_SOURCE[0]}")/../scripts/utils/gpu_config.sh" ]; then
    # shellcheck disable=SC1091
    source "$(dirname "${BASH_SOURCE[0]}")/../scripts/utils/gpu_config.sh"
    # Redirect to stderr to keep stdout clean for scripts that capture output
    detect_and_export_rocm_env >&2 || warn "GPU auto-detection encountered an issue"
fi
