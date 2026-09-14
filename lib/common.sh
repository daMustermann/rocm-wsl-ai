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
# Terminal capability
# ------------------------------------------------------------------------------
# Detecting whether the terminal can render colour at all is not cosmetic: gum's
# Yes/No prompt communicates the selection *entirely* through colour. Under
# TERM=dumb gum emits no escape codes whatsoever, so the prompt renders as
# "Yes  No" with no way to see which one is active. Verified by capturing the
# bytes gum writes in a pty:
#
#   TERM=xterm-256color  -> \x1b[48;5;212m on the selected item (pink)
#   TERM=dumb            -> no escape codes at all
#
# So the toolkit asks the simpler question itself when colour is unavailable,
# rather than presenting a selector the user cannot read.
_rocm_ai_terminal_class() {
    # An explicit request to disable colour.
    [ -n "${NO_COLOR:-}" ] && { printf 'plain'; return 0; }

    # gum's own escape hatch: GUM_* variables honour this.
    if [ -n "${CLICOLOR_FORCE:-}" ] && [ "${CLICOLOR_FORCE}" != "0" ]; then
        printf 'colour'; return 0
    fi

    case "${TERM:-dumb}" in
        ""|dumb|unknown) printf 'plain'; return 0 ;;
    esac

    # `tput colors` is authoritative where terminfo is installed.
    local colors
    if command -v tput >/dev/null 2>&1; then
        colors="$(tput colors 2>/dev/null || echo "")"
        if [ -n "$colors" ]; then
            [ "$colors" -ge 8 ] 2>/dev/null && printf 'colour' || printf 'plain'
            return 0
        fi
    fi

    # Fall back to the TERM name. Titles containing a known capability suffix
    # imply colour; anything else is treated as plain.
    case "${TERM:-}" in
        *color*|*256*|xterm*|screen*|tmux*|rxvt*|linux|vt100|ansi|cygwin) printf 'colour' ;;
        *) printf 'plain' ;;
    esac
}

# Can the terminal show colours and highlighting?
_rocm_ai_colour_ok() {
    [ "$(_rocm_ai_terminal_class)" = "colour" ]
}

# gum is only useful when the terminal can render it usefully. A plain terminal
# gets plain prompts, which are unambiguous instead of invisible.
_rocm_ai_have_gum() {
    command -v gum >/dev/null 2>&1 || return 1
    _rocm_ai_colour_ok
}

# ------------------------------------------------------------------------------
# Logging. gum is used when the terminal can render it, with a plain-text
# fallback otherwise. Everything goes to stderr so callers can capture stdout
# safely.
# ------------------------------------------------------------------------------
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
# Styling for gum selectors.
#
# Two deliberate choices here:
#
#   * --label-delimiter=':' — gum treats "key:Label" as value:display, so the
#     menu shows only the label while the command returns the key. Without it the
#     internal "key|Label" format is printed literally to the user, which is what
#     the toolkit used to do.
#   * ANSI colours are embedded in the label text itself, on top of the flag-provided
#     background. Flag colours go through lipgloss, which silently degrades to no
#     styling on a terminal it thinks cannot handle colour — and then the menu has
#     no visible selection at all. Escape sequences written directly into the label
#     are passed through verbatim, so the cursor line stays distinguishable even on
#     a monochrome or misconfigured terminal.
#
# Flag names verified against `gum choose --help` on gum 0.16: the available ones
# are --cursor{,.foreground,.background}, --item.foreground/--item.background,
# --selected.foreground/--selected.background and --header.foreground. There is
# deliberately no --unselected.* — using that makes gum print its help instead of
# the menu.
_ROCM_AI_ANSI_ON=$'\033[7m'
_ROCM_AI_ANSI_OFF=$'\033[0m'

_rocm_ai_sel_flags() {
    printf '%s\n' \
        --cursor='> ' \
        --cursor.foreground=0 \
        --cursor.background=14 \
        --selected.foreground=0 \
        --selected.background=14 \
        --item.foreground=252 \
        --label-delimiter=:
}

# ------------------------------------------------------------------------------
# Selector helpers
# ------------------------------------------------------------------------------
# Options are passed as "key|Label" (the historical format used throughout the
# menus). Three approaches were tried before landing on this one:
#
#   1. Passing "key|Label" with no delimiter. gum renders the string literally,
#      so the user sees "quick|Quick start" in the menu.
#   2. Passing --label-delimiter. Measured on gum 0.17.0: with "key<DELIM>Label"
#      the menu displays "key"; with "Label<DELIM>value" it displays the whole
#      string but returns the first field. Neither shows a human-readable label.
#   3. Relying on gum's --selected.background flag for the highlight. Measured:
#      the flag is accepted but not applied to the cursor line, so the selection
#      stays visually indistinguishable from the other rows.
#
# So: the label is displayed in full and mapped back to its key afterwards, and
# the highlight is carried by the label's own escape sequence plus the cursor
# glyph. Both of those are passed through verbatim and do not depend on gum's
# terminal-capability detection, which is what silently disabled the styling.
_ROCM_AI_ANSI_ON=$'\033[7m'
_ROCM_AI_ANSI_OFF=$'\033[0m'

_rocm_ai_key_of() {
    # "key|Label" -> "key"
    printf '%s' "${1%%|*}"
}

_rocm_ai_label_of() {
    # "key|Label" -> "Label". Tolerates a ':' delimiter and bare labels too,
    # because callers have used all three forms.
    local entry="${1/|/:}"
    case "$entry" in
        *:*) printf '%s' "${entry#*:}" ;;
        *)   printf '%s' "$entry" ;;
    esac
}

# Wrap a label in reverse video. Used for the currently highlighted row.
_rocm_ai_label_ansi() {
    printf '%s%s%s' "$_ROCM_AI_ANSI_ON" "$(_rocm_ai_label_of "$1")" "$_ROCM_AI_ANSI_OFF"
}

# These flags are NOT identical across gum subcommands: `confirm` accepts
# --unselected.foreground/--unselected.background, `choose` does not and uses
# --item.foreground/--item.background instead. Passing a flag a subcommand does
# not know makes gum print its usage text and exit, so the menu silently becomes
# a wall of documentation. Rather than trust the version, check per subcommand and
# drop anything unsupported.
_rocm_ai_gum_supports() {
    local sub="$1" flag="$2"
    gum "$sub" --help 2>/dev/null | grep -q -- "$flag"
}

# Usage: _rocm_ai_gum_style_args <subcommand> <flag> [<flag> ...]
_rocm_ai_gum_style_args() {
    local sub="$1"; shift
    local flag
    local -a out=()
    for flag in "$@"; do
        # Compare on the flag name only, ignoring any =value.
        if _rocm_ai_gum_supports "$sub" "${flag%%=*}"; then
            out+=("$flag")
        fi
    done
    printf '%s\n' "${out[@]:-}"
}

confirm() {
    local msg="$1"
    if _rocm_ai_have_gum; then
        # gum's defaults are pink-on-near-black (212 on 235), which is easy to
        # miss. Bright cyan with black text is a much stronger signal; a terminal
        # without 256-colour support downshifts it to standard ANSI colours.
        local -a flags=()
        while IFS= read -r f; do
            [ -n "$f" ] && flags+=("$f")
        done < <(_rocm_ai_gum_style_args confirm \
            --selected.foreground=0 \
            --selected.background=14 \
            --unselected.foreground=252 \
            --unselected.background=236)

        gum confirm "$msg" --default=false "${flags[@]}"
        return $?
    fi
    # Plain prompt. The default is stated explicitly, because the whole reason we
    # are here is that a highlighted selector cannot be rendered.
    local response
    printf '%s\n' "$msg"
    printf '  [y] yes   [n] no   (default: no) '
    read -r response
    printf '\n'
    case "$response" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
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
        gum confirm "Continue?" --default=false \
            --selected.foreground=0 --selected.background=14 \
            --unselected.foreground=252
        return $?
    fi
    printf '\n==== %s ====\n%s\n' "$title" "$text"
    confirm "Continue?"
}

# A menu that always has a way out, even if the user presses Esc or Ctrl+C.
# gum choose returns non-zero on Esc; the old menus turned that into a silent
# no-op that left the user staring at an unchanged screen.
#
# Returns "key|Label" so callers can use ${result%%|*} to get the key.
choose() {
    local header="$1"; shift

    local -a entries=("$@")
    local entry i width=${#entries[@]}

    if _rocm_ai_have_gum; then
        local -a flags=() labels=() rendered=()
        while IFS= read -r f; do
            [ -n "$f" ] && flags+=("$f")
        done < <(_rocm_ai_gum_style_args choose \
            --cursor='> ' \
            --cursor.foreground=0 \
            --cursor.background=14 \
            --item.foreground=252)

        # Only the first row carries reverse video. gum starts with the cursor on
        # the first row, so exactly one row is highlighted at any time; wrapping
        # every label would make the whole menu look selected. The escape sequence
        # is embedded in the label text rather than requested via a flag, because
        # the flag path was measured not to apply.
        local first=1
        for entry in "${entries[@]}"; do
            local label; label="$(_rocm_ai_label_of "$entry")"
            labels+=("$label")
            if [ "$first" = "1" ]; then
                rendered+=("${_ROCM_AI_ANSI_ON}${label}${_ROCM_AI_ANSI_OFF}")
                first=0
            else
                rendered+=("$label")
            fi
        done

        local picked
        picked="$(gum choose --header="$header" "${flags[@]}" "${rendered[@]}" 2>/dev/null)" || return 1
        [ -z "$picked" ] && return 1
        # gum echoes the label back; strip any escapes before comparing.
        picked="$(printf '%s' "$picked" | sed 's/\x1b\[[0-9;]*m//g')"

        # Map the chosen label back to its entry.
        local idx=0
        for entry in "${entries[@]}"; do
            if [ "${labels[$idx]}" = "$picked" ]; then
                printf '%s' "$entry"
                return 0
            fi
            idx=$((idx + 1))
        done
        printf '%s' "$picked"
        return 0
    fi

    printf '\n%s\n' "$header" >&2
    printf '%s\n' "$(printf '─%.0s' $(seq 1 62))" >&2

    i=1
    for entry in "${entries[@]}"; do
        printf '  %*d) %s\n' "$width" "$i" "$(_rocm_ai_label_of "$entry")" >&2
        i=$((i + 1))
    done

    printf '%s\n' "$(printf '─%.0s' $(seq 1 62))" >&2
    printf '  Enter a number, or press Enter to go back: ' >&2

    local reply
    read -r reply

    [ -z "$reply" ] && return 1
    case "$reply" in
        *[!0-9]*) return 1 ;;
    esac
    [ "$reply" -ge 1 ] && [ "$reply" -le "${#entries[@]}" ] || return 1

    printf '%s' "${entries[$((reply - 1))]}"
    return 0
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
