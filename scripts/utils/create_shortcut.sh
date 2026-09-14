#!/bin/bash
# ==============================================================================
# Create a Windows desktop shortcut
# ==============================================================================
# Compatibility front-end. The real implementation lives in
# lib/tools.sh::rocm_ai_create_shortcut, which understands the tool registry.
#
# Accepted forms:
#   create_shortcut.sh <tool-key>                    e.g. comfyui
#   create_shortcut.sh "<display name>" <script>     legacy two-argument form
# ==============================================================================
set -uo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export TOOLKIT_ROOT
# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/lib/common.sh"
# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/lib/launch.sh"
# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/lib/tools.sh"

ai_load_env >/dev/null 2>&1 || true

# --- Legacy two-argument form -------------------------------------------------
# Older menu code called: create_shortcut.sh "ComfyUI" /path/to/start/comfyui.sh
# Map that back onto a registry key so both call styles work.
if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then
    legacy_script="$2"
    legacy_key="$(basename "$legacy_script" .sh)"
    if rocm_ai_registry_row "$legacy_key" >/dev/null 2>&1; then
        rocm_ai_create_shortcut "$legacy_key"
        exit $?
    fi
    # Unknown tool: still make a usable shortcut rather than refusing.
    ai_warn "'$legacy_key' is not in the tool registry; creating a plain shortcut."
    name="$1"
    if ! ai_is_wsl; then
        ai_err "Desktop shortcuts require WSL2."
        exit 1
    fi
    win_profile="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r\n')"
    desktop="$(wslpath "$win_profile/Desktop" 2>/dev/null)"
    [ -d "$desktop" ] || { ai_err "Windows Desktop not found."; exit 1; }
    distro_arg=""
    [ -n "${WSL_DISTRO_NAME:-}" ] && distro_arg="-d \"$WSL_DISTRO_NAME\""
    bat="$desktop/${name// /_}.bat"
    {
        printf '@echo off\r\n'
        printf 'title %s  -  ROCm AI Toolkit\r\n' "$name"
        printf 'echo Starting %s ...\r\n' "$name"
        printf 'wsl.exe %s -- bash -l "%s"\r\n' "$distro_arg" "$legacy_script"
        printf 'pause\r\n'
    } > "$bat"
    ai_ok "Shortcut created: ${name// /_}.bat"
    exit 0
fi

# --- Registry form ------------------------------------------------------------
if [ "$#" -lt 1 ]; then
    cat >&2 <<EOF
Usage: $0 <tool-key>
       $0 "<display name>" "<launch script>"

Known tool keys:
$(rocm_ai_all_tool_keys | sed 's/^/  /')
EOF
    exit 1
fi

rocm_ai_create_shortcut "$1"
