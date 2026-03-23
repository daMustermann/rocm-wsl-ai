#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    source "$SCRIPT_DIR/lib/common.sh"
fi

if ! is_wsl; then
    err "Shortcuts can only be created in a WSL environment."
    exit 1
fi

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 \"<Tool Name>\" \"<Launch Script Path>\""
    exit 1
fi

TOOL_NAME="$1"
LAUNCH_SCRIPT="$2"

if ! command -v cmd.exe > /dev/null; then
    err "Cannot find cmd.exe. Ensure Windows interop is enabled."
    exit 1
fi

WIN_PROFILE=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r\n')
if [ -z "$WIN_PROFILE" ]; then
    err "Failed to determine Windows user profile path."
    exit 1
fi

DESKTOP_LINUX_PATH=$(wslpath "$WIN_PROFILE/Desktop")

if [ ! -d "$DESKTOP_LINUX_PATH" ]; then
    err "Windows Desktop directory not found at: $DESKTOP_LINUX_PATH"
    exit 1
fi

SHORTCUT_FILE="$DESKTOP_LINUX_PATH/$TOOL_NAME.bat"

DISTRO_ARG=""
if [ -n "${WSL_DISTRO_NAME:-}" ]; then
    DISTRO_ARG="-d \"$WSL_DISTRO_NAME\""
fi

log "Creating shortcut for $TOOL_NAME at $SHORTCUT_FILE"

# Use printf with \r\n to ensure DOS CRLF line endings
printf "@echo off\r\necho Starting %s in WSL...\r\nwsl.exe %s ~ -e bash -ic \"%s\"\r\npause\r\necho Exiting...\r\n" "$TOOL_NAME" "$DISTRO_ARG" "$LAUNCH_SCRIPT" > "$SHORTCUT_FILE"

success "Shortcut successfully created on your Windows Desktop!"
