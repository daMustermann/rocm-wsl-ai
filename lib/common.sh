#!/bin/bash
# Shared utilities for installer scripts
set -o pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log(){ echo -e "${BLUE}[INFO]${NC} $*" >&2; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
err(){ echo -e "${RED}[ERROR]${NC} $*" >&2; }
success(){ echo -e "${GREEN}[OK]${NC} $*" >&2; }
headline(){ echo -e "${MAGENTA}==== $* ====${NC}" >&2; }

confirm(){ local m="$1"; read -p "${m} (y/N): " -r r; [[ $r =~ ^[Yy]$ ]]; }

ensure_venv(){ local n="$1"; local p="$HOME/$n"; if [ ! -f "$p/bin/activate" ]; then err "venv not found: $p"; return 1; fi; # shellcheck disable=SC1090
  source "$p/bin/activate"; success "Activated venv '$n' (python $(python -V 2>&1))"; }

git_clone_or_update(){ local url="$1" dir="$2"; if [ ! -d "$dir/.git" ]; then log "Cloning $url"; git clone --depth=1 "$url" "$dir" || return 1; else log "Updating $dir"; git -C "$dir" pull --rebase --autostash || warn "Git update issues"; fi; }

pip_install_if_exists(){ local f="$1"; [ -f "$f" ] || { warn "No requirements: $f"; return 0; }; log "Installing $(basename "$f")"; pip install --no-cache-dir -r "$f"; }

ensure_apt_packages(){ [ $# -eq 0 ] && return 0; log "Ensuring apt packages: $*"; sudo apt update -y >/dev/null; sudo apt install -y "$@"; }

install_powershell_hint(){
  warn "Automatic installation of PowerShell failed or is not available for your distribution."
  echo "You can try the following manual steps in WSL to install PowerShell:" >&2
  echo "  sudo apt update" >&2
  echo "  sudo apt install -y powershell" >&2
  echo "If the package is not available, follow Microsoft docs: https://learn.microsoft.com/powershell/scripting/install/install-ubuntu" >&2
}

is_wsl(){ grep -qi microsoft /proc/version 2>/dev/null; }
has_rocm(){ command -v rocminfo >/dev/null 2>&1; }

standard_header(){ headline "$1"; is_wsl && log "Environment: WSL"; has_rocm && log "ROCm detected" || warn "ROCm NOT detected"; }

export -f log warn err success headline confirm ensure_venv git_clone_or_update pip_install_if_exists ensure_apt_packages is_wsl has_rocm standard_header

# Optional GPU auto-detection (idempotent)
GPU_ENV_MARKER="${HOME}/.config/rocm-wsl-ai/gpu.env"
if [ -f "$(dirname "${BASH_SOURCE[0]}")/../scripts/utils/gpu_config.sh" ]; then
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../scripts/utils/gpu_config.sh"

  # Always run detection to set env vars and regenerate the env file.
  # This fixes issues with stale or malformed gpu.env files from previous versions.
  # Redirecting to stderr to avoid polluting stdout for scripts that source this.
  detect_and_export_rocm_env >&2 || warn "GPU auto-detection failed"
fi
