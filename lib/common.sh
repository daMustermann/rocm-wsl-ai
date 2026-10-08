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

# The same palette expressed as hex, for gum's `style`, which takes hex, and as
# 256-colour indices for gum's `choose`, which takes indices. One palette in one
# place: these are the values the upstream log/headline helpers already used
# (117/214/196/46/212), so the gum and ANSI renderings cannot drift apart.
_GUM_INFO=117;   _GUM_INFO_HEX='#749cdb'    # informational
_GUM_WARN=214;   _GUM_WARN_HEX='#ffd75f'    # warnings
_GUM_ERR=196;    _GUM_ERR_HEX='#ff5f5f'     # errors
_GUM_OK=46;      _GUM_OK_HEX='#5fff87'      # success
_GUM_ACCENT=212; _GUM_ACCENT_HEX='#ff87d7'  # headings, selection, borders
_GUM_HEADER=99;  _GUM_HEADER_HEX='#af87ff'  # menu headers
_GUM_MUTED_HEX='#8a8a8a'                    # help text and secondary detail
_GUM_TEXT_HEX='#c8c8c8'                     # body text inside boxes
_GUM_CURSOR_GLYPH='❯ '                       # menu selection marker

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
log()     { if _rocm_ai_have_gum; then gum style --foreground "$_GUM_INFO_HEX"   "ℹ  $*" >&2; else printf '%b[INFO]%b %s\n'  "$BLUE"   "$NC" "$*" >&2; fi; }

warn()    { if _rocm_ai_have_gum; then gum style --foreground "$_GUM_WARN_HEX"   "⚠  $*" >&2; else printf '%b[WARN]%b %s\n'  "$YELLOW" "$NC" "$*" >&2; fi; }
err()     { if _rocm_ai_have_gum; then gum style --foreground "$_GUM_ERR_HEX"    "✖  $*" >&2; else printf '%b[ERROR]%b %s\n' "$RED"    "$NC" "$*" >&2; fi; }
success() { if _rocm_ai_have_gum; then gum style --foreground "$_GUM_OK_HEX"     "✔  $*" >&2; else printf '%b[OK]%b %s\n'    "$GREEN"  "$NC" "$*" >&2; fi; }

headline() {
    if _rocm_ai_have_gum; then
        printf '\n' >&2
        gum style --bold --foreground "$_GUM_ACCENT_HEX" --border normal \
            --border-foreground "$_GUM_ACCENT_HEX" --padding "0 2" "$*" >&2
    else
        printf '\n%b%s==== %s ====%b\n' "$BOLD" "$MAGENTA" "$*" "$NC" >&2
    fi
}

# ------------------------------------------------------------------------------
# Interaction
# ------------------------------------------------------------------------------
# Styling for selectors.
#
# The menu is drawn by us with ANSI escapes, so the highlight is carried by a
# reverse-video sequence rather than by a library's colour flags. That matters:
# terminal-capability detection in styling libraries silently drops colours on
# a terminal it misjudges, which leaves a menu with no visible selection at all.
# Escape sequences written straight into the output cannot be dropped that way.

# ------------------------------------------------------------------------------
# Interactive selection
# ------------------------------------------------------------------------------
# `gum choose` renders its list on stderr and writes the selection to stdout, so
# the obvious way to call it is `result=$(gum choose ...)`. That does not work:
# when stdout is a PIPE, gum cannot render, never reads keystrokes, and hangs
# indefinitely on a blank screen. The same hang was measured on this project's
# live WSL box — the process sat for 90s producing no output and had to be
# killed, and it survives `timeout -s KILL` because the renderer keeps the pty.
#
# Redirection to a FILE works fine with the same gum version (v0.17.0), measured:
#
#     gum choose "alpha" "beta" > /tmp/out   # -> /tmp/out contains "alpha"
#     R=$(gum choose "alpha" "beta")        # -> hangs, never returns
#
# So gum is given a temporary file as its stdout and this function cats that file
# to its own stdout. gum never sees a pipe, and the caller's `$( ... )` keeps
# working because the value it captures is a plain file read.
#
# The hand-rolled cursor menu below stays as the fallback for terminals without
# gum, and as the safety net if gum misbehaves. A menu that hangs is worse than
# an ugly one, so nothing here is allowed to be the only path.
#
# Options are accepted as "key|Label" (the historical format used across the
# menus) and returned in the same form, so callers keep using ${result%%|*}.
_ROCM_AI_SEL_ANSI_ON=$'\033[7m'
_ROCM_AI_SEL_ANSI_OFF=$'\033[0m'

_rocm_ai_label_of() {
    # Entries are "key|Label", which is the format the menus use. Some keys
    # contain a colon themselves ("tool:comfyui|ComfyUI"), so '|' has to win:
    # splitting on the first colon instead left the menu showing
    # "comfyui:ComfyUI  (installed)" — the key, not the label.
    # Tolerates a bare "key:Label" and a bare label too.
    case "$1" in
        *\|*) printf '%s' "${1#*|}" ;;
        *:*)  printf '%s' "${1#*:}" ;;
        *)    printf '%s' "$1" ;;
    esac
}

# Fallback for terminals that cannot do cursor control: numbered input.
_rocm_ai_choose_plain() {
    local header="$1"; shift
    local -a entries=("$@")
    local i=1 entry

    printf '\n%s\n' "$header" >&2
    printf '%s\n' "$(printf -- '-%.0s' $(seq 1 62))" >&2
    for entry in "${entries[@]}"; do
        printf '  %2d) %s\n' "$i" "$(_rocm_ai_label_of "$entry")" >&2
        i=$((i + 1))
    done
    printf '%s\n' "$(printf -- '-%.0s' $(seq 1 62))" >&2
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

# Preferred selector: gum's own menu, fed a temporary file as stdout.
#
# Returns the selected entry on stdout (which may legitimately be a pipe, since
# gum has already exited by the time we write here).
_rocm_ai_choose_gum() {
    local header="$1"; shift
    local -a entries=("$@")

    local tmp rc selection=""
    tmp="$(mktemp "${TMPDIR:-/tmp}/rocm_ai_menu.XXXXXX")" || return 1

    # Only long-standing flags are used here. `choose` takes 256-colour indices
    # rather than hex (its defaults are literally "212" and "99"), and an
    # invented flag such as --selected.cursor makes gum exit before drawing
    # anything — which shows up as an empty menu and a silent return.
    gum choose \
        --header "$header" \
        --cursor "$_GUM_CURSOR_GLYPH" \
        --cursor.foreground "$_GUM_ACCENT" \
        --selected.foreground "$_GUM_ACCENT" \
        --header.foreground "$_GUM_HEADER" \
        "${entries[@]}" > "$tmp"
    rc=$?

    if [ "$rc" -eq 0 ] && [ -s "$tmp" ]; then
        IFS= read -r selection < "$tmp" || selection=""
    fi
    rm -f "$tmp"

    [ -n "$selection" ] || return 1
    printf '%s' "$selection"
    return 0
}

choose() {
    local header="$1"; shift
    local -a entries=("$@")
    local n=${#entries[@]}

    [ "$n" -eq 0 ] && return 1
    [ "$n" -eq 1 ] && { printf '%s' "${entries[0]}"; return 0; }

    # The interactive menu needs a terminal to read keys from AND a terminal to
    # draw on. Testing stdin alone is not enough: when output is piped or
    # redirected the drawing goes nowhere and the menu looks frozen.
    if [ -t 0 ] && [ -t 2 ] && _rocm_ai_colour_ok; then
        # gum renders with proper borders, scrolling and multi-column wrapping,
        # so prefer it — but only if it comes back with something.
        if _rocm_ai_have_gum; then
            _rocm_ai_choose_gum "$header" "${entries[@]}" && return 0
            # A cancelled gum menu and a failed one look the same (nothing on
            # stdout), and both mean "the user backed out". Do not silently
            # re-prompt with a second menu in that case; fall through only when
            # gum was not usable at all.
            return 1
        fi
        _rocm_ai_choose_interactive "$header" "${entries[@]}"
        return $?
    fi

    _rocm_ai_choose_plain "$header" "${entries[@]}"
    return $?
}

# Cursor-driven menu with arrow keys. Visuals are written to stderr and only the
# result goes to stdout, so capturing the result cannot break the display.
_rocm_ai_choose_interactive() {
    local header="$1"; shift
    local -a entries=("$@")
    local n=${#entries[@]}

    local selected=0
    local drawn=0
    local key rest item idx

    # Everything visual goes to stderr; stdout carries only the result.
    _ai_menu_draw() {
        if [ "$drawn" = "1" ]; then
            printf '\033[%dA' "$((n + 3))" >&2
        fi
        printf '\033[J' >&2
        printf '  %s\n' "$header" >&2
        printf '  %s\n' "$(printf -- '-%.0s' $(seq 1 60))" >&2
        idx=0
        for item in "${entries[@]}"; do
            if [ "$idx" -eq "$selected" ]; then
                printf '  %s> %s%s\n' "$_ROCM_AI_SEL_ANSI_ON" \
                    "$(_rocm_ai_label_of "$item")" "$_ROCM_AI_SEL_ANSI_OFF" >&2
            else
                printf '    %s\n' "$(_rocm_ai_label_of "$item")" >&2
            fi
            idx=$((idx + 1))
        done
        printf '  %s\n' "$(printf -- '-%.0s' $(seq 1 60))" >&2
        printf '  up/down move   enter select   q cancel\n' >&2
        drawn=1
    }

    printf '\033[?25l' >&2    # hide the cursor while navigating
    _ai_menu_draw

    while true; do
        if ! IFS= read -rsn1 key; then
            printf '\033[?25h\n' >&2
            return 1
        fi

        case "$key" in
            $'\x1b')
                IFS= read -rsn1 -t 1 rest || rest=""
                if [ "$rest" = "[" ]; then
                    IFS= read -rsn1 -t 1 key || key=""
                    case "$key" in
                        A) selected=$(( (selected - 1 + n) % n )); _ai_menu_draw ;;
                        B) selected=$(( (selected + 1) % n )); _ai_menu_draw ;;
                    esac
                else
                    printf '\033[?25h\n' >&2    # bare Escape cancels
                    return 1
                fi
                ;;
            k) selected=$(( (selected - 1 + n) % n )); _ai_menu_draw ;;
            j) selected=$(( (selected + 1) % n )); _ai_menu_draw ;;
            q|Q)
                printf '\033[?25h\n' >&2
                return 1
                ;;
            "")
                printf '\033[?25h\n' >&2
                printf '%s' "${entries[$selected]}"
                return 0
                ;;
            [1-9])
                # A digit jumps straight to that option.
                if [ "$key" -le "$n" ]; then
                    selected=$((key - 1))
                    _ai_menu_draw
                fi
                ;;
            *) : ;;
        esac
    done
}

confirm() {
    local msg="$1"
    local response

    # Read a single key directly rather than delegating to a TUI for the same
    # reason as choose(): a prompt whose output is captured cannot rely on an
    # external renderer being able to draw.
    if [ -t 0 ] && _rocm_ai_colour_ok; then
        printf '  %s  [y/N] ' "$msg" >&2
        IFS= read -rsn1 response || response=""
        printf '%s\n' "$response" >&2
    else
        printf '%s\n' "$msg"
        printf '  [y] yes   [n] no   (default: no) '
        read -r response
        printf '\n'
    fi

    case "$response" in
        y|Y) return 0 ;;
        *)   return 1 ;;
    esac
}

# ------------------------------------------------------------------------------
# Message boxes and two-part confirmations
# ------------------------------------------------------------------------------
# Both of these are called ~19 times from menu.sh and were exported below without
# ever being defined, so every call site ran `command not found`. That silently
# broke the confirmation gate on `install_base`: `if ! yesno ...` evaluated 127,
# which `!` turned into success, so the base environment installed itself with no
# prompt at all.
#
# Bodies arrive as double-quoted strings containing literal `\n`, so they are
# expanded through printf '%b' before being handed to any renderer.

# `_rocm_ai_expand_body` — turn literal \n and \t into real control characters.
_rocm_ai_expand_body() {
    printf '%b' "$1"
}

# msgbox TITLE BODY — show a titled box and wait for a keypress.
msgbox() {
    local title="$1" body
    body="$(_rocm_ai_expand_body "${2:-}")"

    printf '\n' >&2
    if _rocm_ai_have_gum && [ -t 2 ]; then
        {
            printf '%s\n' "$title"
            [ -n "$body" ] && printf '\n%s\n' "$body"
        } | gum style --border rounded --border-foreground "$_GUM_ACCENT_HEX" \
            --padding "0 2" --margin "0 1" --foreground "$_GUM_TEXT_HEX" >&2
    else
        local rule
        rule="$(printf -- '-%.0s' $(seq 1 62))"
        printf '%s\n' "$rule" >&2
        printf ' %s\n' "$title" >&2
        [ -n "$body" ] && { printf '\n' >&2; printf '%s\n' "$body" >&2; }
        printf '%s\n' "$rule" >&2
    fi

    if [ -t 0 ]; then
        printf '  press any key to continue ... ' >&2
        IFS= read -rsn1 _ || true
        printf '\n' >&2
    fi
    return 0
}

# yesno TITLE BODY — a titled confirmation. Returns 0 for yes, 1 for no or abort.
yesno() {
    local title="$1" body response

    # gum confirm obeys the same stdout rule as gum choose, and the failure mode
    # is worse: with stdout on the terminal it never returns and the prompt sits
    # there ignoring every keypress until it is killed. Measured on gum v0.17.0 —
    #     gum confirm "Proceed?"              # hangs, ignoring 'y' and enter
    #     gum confirm "Proceed?" > /tmp/ans   # returns 0 for yes, 1 for no
    #
    # Note that v0.17.0 writes NOTHING to stdout — verified by dumping the file,
    # which comes back zero bytes. The answer exists only in the exit status, so
    # that is what is used here; reading a "Yes"/"No" string would silently
    # report every prompt as "no".
    if _rocm_ai_have_gum && [ -t 0 ] && [ -t 2 ]; then
        if [ -n "${2:-}" ]; then
            printf '\n%s\n\n%s\n\n' "$title" "$(_rocm_ai_expand_body "$2")" >&2
        else
            printf '\n%s\n\n' "$title" >&2
        fi

        local tmp rc=1
        tmp="$(mktemp "${TMPDIR:-/tmp}/rocm_ai_confirm.XXXXXX")" || tmp=""
        if [ -n "$tmp" ]; then
            gum confirm "Proceed?" > "$tmp" 2>/dev/null
            rc=$?
            rm -f "$tmp"
        else
            gum confirm "Proceed?" >/dev/null 2>&1
            rc=$?
        fi

        [ "$rc" -eq 0 ] && return 0
        return 1
    fi

    printf '\n%s\n' "$title" >&2
    if [ -n "${2:-}" ]; then
        printf '\n%s\n' "$(_rocm_ai_expand_body "$2")" >&2
    fi
    printf '  [y] yes   [n] no   (default: no) ' >&2
    read -r response
    printf '\n' >&2
    case "$response" in
        y|Y) return 0 ;;
        *)   return 1 ;;
    esac
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

# ROCm 10.x ships librocdxg inside its own artifacts and the ROCr runtime
# auto-detects /dev/dxg, so a stock 10.x install has no standalone build step.
# ROCm 7.2.x required building it from source with the Windows SDK. Accept
# either layout, and search the Core SDK prefix too, not just /opt/rocm.
has_rocdxg() {
    local candidate
    for candidate in \
        /opt/rocm/lib/librocdxg.so \
        /opt/rocm/core-*/lib/librocdxg.so \
        /usr/lib/librocdxg.so \
        /usr/local/lib/librocdxg.so
    do
        [ -e "$candidate" ] && return 0
    done
    return 1
}

# The WSL GPU bridge device. ROCr looks for this to decide it is on WSL at all;
# without it no amount of ROCm installation will make a GPU appear.
has_dxg_device() { [ -c /dev/dxg ]; }

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
        if ! has_dxg_device; then
            err "/dev/dxg is missing — WSL2 cannot reach the GPU at all."
            err "  Close every WSL window, then from PowerShell run:  wsl --shutdown"
            err "  Reopen WSL and start the toolkit again."
            problems=$((problems + 1))
        fi
        if ! has_rocdxg; then
            warn "librocdxg not found."
            warn "  On ROCm 10.x it ships with ROCm; reinstall the base environment."
            warn "  On ROCm 7.2.x it must be built from source (Windows SDK required)."
            problems=$((problems + 1))
        fi
    fi

    if [ ! -f "$HOME/genai_env/bin/activate" ]; then
        log "Base environment not installed yet (~/genai_env missing)."
    fi

    # ROCr auto-detects WSL and defaults HSA_ENABLE_DXG_DETECTION to 1, so this
    # only needs exporting on legacy 7.2.x stacks that predate ROCr 7.13.
    if [ -n "${HSA_OVERRIDE_GFX_VERSION:-}" ]; then
        warn "HSA_OVERRIDE_GFX_VERSION is set to '${HSA_OVERRIDE_GFX_VERSION}'."
        warn "  Under WSL this makes the runtime reject the device and hides your GPU."
        warn "  Remove it from $USER_ENV"
        problems=$((problems + 1))
    fi

    # A ROCr-7.2-era trap that an older toolkit actively recommended. torch 2.9.1
    # and 2.10.0 segfault on import with this set.
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
# HSA_OVERRIDE_GFX_VERSION forces a GPU architecture. It MUST NOT be set under
# WSL: DXCore enumerates the GPU itself, and an override makes the runtime reject
# the device, hiding your GPU from PyTorch entirely.
# Leave commented out unless you know you need it on native Linux.
# export HSA_OVERRIDE_GFX_VERSION="gfx1100"

# Limit which GPUs are visible on multi-GPU systems (0, 1, 0,1 ...).
# Leave commented out to expose every GPU.
# export ROCR_VISIBLE_DEVICES="0"

# The WSL DXCore bridge. ROCr 7.13 and newer (including all of ROCm 10.x) detect
# WSL automatically and default this to 1, so the line below is only a safety net
# for legacy 7.2.x stacks. Do not change.
export HSA_ENABLE_DXG_DETECTION=1

# Which ROCm 10.x architecture package and torch device extra were installed
# (for example gfx1100). Filled in by the installer; used to reinstall matching
# wheels if the environment ever has to be rebuilt.
export AMDROCM_DEVICE_TARGET=""

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
