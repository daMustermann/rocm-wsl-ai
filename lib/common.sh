#!/bin/bash
# ==============================================================================
# ROCm WSL AI Toolkit — Shared shell utilities
# ==============================================================================
# Sourced by every script in the toolkit. Intentionally does NO work at source
# time: no GPU detection, no subprocess calls, no config writes.
#
# The previous version ran GPU auto-detection (which shells out to `rocminfo`
# and PowerShell) on every single source, adding seconds to startup and writing
# files as a side effect of merely importing the library. That work now happens
# explicitly, once, via ai_load_env / ai_preflight in lib/launch.sh, and the
# results are cached.
# ==============================================================================

# Deliberately NOT `set -e`: a library should not change the shell's error
# semantics for its callers.
set -o pipefail

# ------------------------------------------------------------------------------
# Version — single source of truth.
# ------------------------------------------------------------------------------
_rocm_ai_version_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/VERSION"
if [ -f "$_rocm_ai_version_file" ]; then
    ROCM_AI_VERSION="$(tr -d ' \r\n' < "$_rocm_ai_version_file")"
else
    ROCM_AI_VERSION="unknown"
fi
unset _rocm_ai_version_file

# ------------------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------------------
ROCM_AI_CONFIG_DIR="${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}"
USER_ENV="$ROCM_AI_CONFIG_DIR/user.env"
GPU_ENV="$ROCM_AI_CONFIG_DIR/gpu.env"
ROCM_AI_LOG_DIR="$ROCM_AI_CONFIG_DIR/logs"

# ------------------------------------------------------------------------------
# Colours (suppressed when not writing to a terminal)
# ------------------------------------------------------------------------------
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

# ------------------------------------------------------------------------------
# Logging. gum is used when available, with a plain-text fallback.
# Everything goes to stderr so that callers can capture stdout safely.
# ------------------------------------------------------------------------------
_rocm_ai_have_gum() { command -v gum >/dev/null 2>&1; }

log()     { if _rocm_ai_have_gum; then gum style --foreground 117 "ℹ  $*" >&2; else printf '%b[INFO]%b %s\n' "$BLUE" "$NC" "$*" >&2; fi; }
warn()    { if _rocm_ai_have_gum; then gum style --foreground 214 "⚠  $*" >&2; else printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$*" >&2; fi; }
err()     { if _rocm_ai_have_gum; then gum style --foreground 196 "✖  $*" >&2; else printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$*" >&2; fi; }
success() { if _rocm_ai_have_gum; then gum style --foreground 46 "✔  $*" >&2; else printf '%b[OK]%b %s\n' "$GREEN" "$NC" "$*" >&2; fi; }

headline() {
    if _rocm_ai_have_gum; then
        printf '\n' >&2
        gum style --bold --foreground 212 --border normal --border-foreground 212 \
            --padding "0 2" "$*" >&2
    else
        printf '\n%b%s==== %s ====%b\n' "$BOLD" "$MAGENTA" "$*" "$NC" >&2
    fi
}

# ------------------------------------------------------------------------------
# Interaction
# ------------------------------------------------------------------------------
confirm() {
    local msg="$1"
    if _rocm_ai_have_gum; then
        gum confirm "$msg" --default=false
    else
        local response
        read -rp "${msg} (y/N): " -r response
        [[ "$response" =~ ^[Yy]$ ]]
    fi
}

msgbox() {
    local title="$1" text="$2"
    printf '\n'
    if _rocm_ai_have_gum; then
        printf '%s\n\n%s\n' "$(gum style --bold --foreground 212 "$title")" "$text" \
            | gum style --border rounded --margin "0 2" --padding "1 2" --border-foreground 212
    else
        printf '\n==== %s ====\n%s\n' "$title" "$text"
    fi
    printf '\n'
    read -rp "  Press Enter to continue..."
}

yesno() {
    local title="$1" text="$2"
    printf '\n'
    if _rocm_ai_have_gum; then
        printf '%s\n\n%s\n' "$(gum style --bold --foreground 214 "$title")" "$text" \
            | gum style --border normal --margin "0 2" --padding "1 2" --border-foreground 214
        printf '\n'
        gum confirm "Continue?" --default=false
    else
        printf '\n==== %s ====\n%s\n' "$title" "$text"
        confirm "Continue?"
    fi
}

# A menu that always has a way out, even if the user presses Esc or Ctrl+C.
# gum choose returns non-zero on Esc; the old menus turned that into a silent
# no-op that left the user staring at an unchanged screen.
choose() {
    local header="$1"; shift
    if _rocm_ai_have_gum; then
        local choice
        choice="$(gum choose --cursor='» ' --header="$header" "$@" 2>/dev/null)" || return 1
        printf '%s' "$choice"
    else
        local i=1 option
        printf '\n%s\n' "$header" >&2
        for option in "$@"; do
            printf '  %2d) %s\n' "$i" "$option" >&2
            i=$((i + 1))
        done
        local reply
        read -rp "  Choice (blank to go back): " reply
        [ -z "$reply" ] && return 1
        [ "$reply" -ge 1 ] 2>/dev/null && [ "$reply" -lt "$i" ] || return 1
        printf '%s' "${!reply}"
    fi
}

# ------------------------------------------------------------------------------
# Environment checks
# ------------------------------------------------------------------------------
is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null \
        || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

require_wsl() {
    if ! is_wsl; then
        err "This toolkit targets Windows Subsystem for Linux (WSL2)."
        err "On native Linux, use AMD's official ROCm documentation instead."
        return 1
    fi
}

has_rocm()     { command -v rocminfo >/dev/null 2>&1; }
has_rocdxg()   { [ -f "/opt/rocm/lib/librocdxg.so" ]; }

has_windows_sdk() {
    local base="/mnt/c/Program Files (x86)/Windows Kits/10/Include"
    [ -d "$base" ] || return 1
    local ver
    ver="$(ls -1 "$base" 2>/dev/null | grep -E '^10\.' | sort -V | tail -1)"
    [ -n "$ver" ]
}

# Sanity-check the things that are cheap and catch the most common breakages.
check_environment() {
    local problems=0

    if is_wsl; then
        if ! has_rocdxg; then
            warn "ROCDXG (librocdxg.so) is missing — GPU compute will not work in WSL2."
            problems=$((problems + 1))
        fi
    fi

    if [ ! -f "$HOME/genai_env/bin/activate" ]; then
        log "Base environment not installed yet (~/genai_env missing)."
    fi

    # The variable below segfaults torch 2.9.1+rocm7.2.3 on import. An earlier
    # toolkit version actively migrated users towards it.
    if [ -n "${PYTORCH_HIP_ALLOC_CONF:-}" ]; then
        warn "PYTORCH_HIP_ALLOC_CONF is set and crashes this PyTorch build."
        warn "  Remove it from ~/.bashrc or $USER_ENV"
        problems=$((problems + 1))
    fi

    return $((problems > 0))
}

check_not_root() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        warn "Running as root is not recommended; sudo is requested only when needed."
        confirm "Continue anyway?" || return 1
    fi
}

# ------------------------------------------------------------------------------
# Virtual environments
# ------------------------------------------------------------------------------
ensure_venv() {
    local venv_name="$1"
    local venv_path="$HOME/$venv_name"
    if [ ! -f "$venv_path/bin/activate" ]; then
        err "Python environment not found: $venv_path"
        return 1
    fi
    # shellcheck disable=SC1090
    . "$venv_path/bin/activate"
    local py_ver
    py_ver="$(python3 --version 2>&1 | awk '{print $2}')"
    success "Activated '$venv_name' (Python $py_ver)"
}

# ------------------------------------------------------------------------------
# Git and packages
# ------------------------------------------------------------------------------
git_clone_or_update() {
    local url="$1" dir="$2"
    if [ ! -d "$dir/.git" ]; then
        log "Cloning $url"
        git clone --depth=1 --recurse-submodules "$url" "$dir" \
            || { err "Failed to clone $url"; return 1; }
    else
        log "Updating $dir"
        git -C "$dir" pull --rebase --autostash || warn "git pull had issues (continuing)"
        if [ -f "$dir/.gitmodules" ]; then
            git -C "$dir" submodule sync --recursive >/dev/null 2>&1 || true
            git -C "$dir" submodule update --init --recursive || warn "submodule update had issues"
        fi
    fi
}

ensure_apt_packages() {
    [ $# -eq 0 ] && return 0
    log "Ensuring system packages: $*"
    sudo apt-get update -y >/dev/null 2>&1
    sudo apt-get install -y "$@" || { err "Failed to install: $*"; return 1; }
}

# ------------------------------------------------------------------------------
# Legacy compatibility shims
# ------------------------------------------------------------------------------
# Kept so that older scripts and any user automation that sourced this library
# still work. New code should use lib/launch.sh instead.

standard_header() {
    headline "$1"
    if is_wsl; then
        log "Environment: WSL2"
    else
        warn "Environment: native Linux (unsupported)"
    fi
    if has_rocm; then
        log "ROCm: detected"
    else
        warn "ROCm: not detected — install the base environment first"
    fi
}

load_user_env() {
    if [ -f "$USER_ENV" ]; then
        set -a
        # shellcheck disable=SC1090
        . "$USER_ENV"
        set +a
    fi
    return 0
}

ensure_user_env() {
    [ -f "$USER_ENV" ] && return 0
    mkdir -p "$ROCM_AI_CONFIG_DIR"
    cat > "$USER_ENV" << 'USERENV_EOF'
# ============================================================
# ROCm WSL AI Toolkit — user settings
# Edit via:  ./menu.sh  ->  Settings  ->  Edit settings
# ============================================================

# --- GPU ---------------------------------------------------
# HSA_OVERRIDE_GFX_VERSION forces a GPU architecture. With ROCm 7.x + ROCDXG it
# MUST NOT be set: DXCore enumerates the GPU itself, and an override makes the
# runtime reject the device, hiding your GPU from PyTorch entirely.
# Leave commented out unless you know you need it on native Linux.
# export HSA_OVERRIDE_GFX_VERSION="gfx1100"

# Limit which GPUs are visible on multi-GPU systems (0, 1, 0,1 ...).
# Leave commented out to expose every GPU.
# export ROCR_VISIBLE_DEVICES="0"

# The WSL DXCore bridge. Must be 1. Do not change.
export HSA_ENABLE_DXG_DETECTION=1

# --- Ports -------------------------------------------------
# Blank means "use the tool's default".
export COMFYUI_PORT=""    # default 8188
export SDNEXT_PORT=""     # default 7860
export A1111_PORT=""      # default 7860
export KOHYA_PORT=""      # default 7861
export TEXTGEN_PORT=""    # default 5000

# --- Behaviour ---------------------------------------------
# How long a tool may sit idle before it is stopped and its VRAM released.
# Set SMART_SLEEP_DISABLE=1 to keep tools running indefinitely.
export SMART_SLEEP_TIMEOUT=1800
USERENV_EOF
    log "Created default settings at $USER_ENV"
}

# Update a single key in user.env, writing `unset KEY` for empty values so that
# an empty export can never hide every GPU from ROCm.
_update_user_env() {
    local key="$1" value="$2"
    ensure_user_env
    if [ -z "$value" ]; then
        sed -i "/^export ${key}=/d" "$USER_ENV"
        grep -q "^unset ${key}" "$USER_ENV" 2>/dev/null || printf 'unset %s\n' "$key" >> "$USER_ENV"
    elif grep -q "^export ${key}=" "$USER_ENV" 2>/dev/null; then
        sed -i "s|^export ${key}=.*|export ${key}=\"${value}\"|" "$USER_ENV"
    else
        sed -i "/^unset ${key}/d" "$USER_ENV"
        printf 'export %s="%s"\n' "$key" "$value" >> "$USER_ENV"
    fi
}

# ------------------------------------------------------------------------------
# Exported names (for scripts that invoke helpers through `bash -c`).
# ------------------------------------------------------------------------------
_rocm_ai_exports=(
    log warn err success headline confirm msgbox yesno choose
    is_wsl require_wsl has_rocm has_rocdxg has_windows_sdk check_environment
    check_not_root ensure_venv git_clone_or_update ensure_apt_packages
    standard_header load_user_env ensure_user_env _update_user_env
)
for _fn in "${_rocm_ai_exports[@]}"; do
    # shellcheck disable=SC2086
    export -f "$_fn" 2>/dev/null || true
done
unset _fn _rocm_ai_exports
