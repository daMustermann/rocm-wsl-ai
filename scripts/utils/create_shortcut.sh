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

# Generate the BAT file with correct wsl.exe syntax and CRLF line endings.
#
# Key fix: the old command `wsl.exe %s ~ -e bash -ic "%s"` was broken:
#   - `~` is not a valid positional argument here (should be --cd ~)
#   - `-e` is a wsl.exe flag meaning "execute without default shell", not a
#     bash flag — so the shell quoting was being misinterpreted
#
# Correct pattern: `wsl.exe [-d Distro] -- bash -l "/path/to/script"`
#   - `--` separates wsl.exe options from the Linux command
#   - `bash -l` launches a login shell (sources .profile/.bashrc, loads env)
#   - The script path is passed as a positional argument (no quoting issues)
{
printf '@echo off\r\n'
printf 'title %s \x2014 ROCm AI Toolkit\r\n'                          "$TOOL_NAME"
printf 'echo.\r\n'
printf 'echo  ==========================================\r\n'
printf 'echo   %s  \x2014  ROCm AI Toolkit\r\n'                       "$TOOL_NAME"
printf 'echo  ==========================================\r\n'
printf 'echo   Loading WSL \x2014 this may take a few seconds.\r\n'
printf 'echo   Once started, open: http://localhost:PORT\r\n'
printf 'echo   Close this window to stop the server.\r\n'
printf 'echo  ==========================================\r\n'
printf 'echo.\r\n'
printf 'wsl.exe %s -- bash -l "%s"\r\n'                                "$DISTRO_ARG" "$LAUNCH_SCRIPT"
printf 'echo.\r\n'
printf 'echo  Server stopped. Press any key to close this window.\r\n'
printf 'pause\r\n'
} > "$SHORTCUT_FILE"

success "Shortcut successfully created on your Windows Desktop!"
