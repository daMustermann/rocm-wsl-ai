#!/bin/bash
# ==============================================================================
# Repair / upgrade the ROCm stack and the ROCDXG WSL bridge
# ==============================================================================
# Thin wrapper around the toolkit's automatic upgrade.
#
# This file used to contain its own ROCm installation logic with hardcoded
# versions (ROCm 7.2.3, PyTorch 2.9.1, amdgpu-install 7.2.3.70203-1). That is
# exactly the duplication that caused the installer and the upgrader to disagree
# with each other, and every AMD patch release invalidated it.
#
# All of that now lives in one place:
#   lib/version.sh   — discovers the newest ROCm release and matching wheels
#   upgrade.sh       — performs the upgrade
#
# Usage:
#   scripts/install/upgrade_to_rocdxg.sh            upgrade ROCm + ROCDXG
#   scripts/install/upgrade_to_rocdxg.sh --check    report only
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export TOOLKIT_ROOT

UPGRADE="$TOOLKIT_ROOT/upgrade.sh"

if [ ! -f "$UPGRADE" ]; then
    echo "error: upgrade.sh not found at $UPGRADE" >&2
    echo "       update the toolkit first:  git -C '$TOOLKIT_ROOT' pull" >&2
    exit 1
fi

printf '\n'
printf '  This now runs the toolkit\x27s automatic upgrade, which handles the\n'
printf '  ROCm stack, the ROCDXG bridge, PyTorch, and your settings together.\n'
printf '\n'

# Default to "leave the toolkit itself alone" only if the caller asked for a
# ROCm-only repair; otherwise let the full upgrade run so the libraries driving
# it are current.
exec bash "$UPGRADE" "$@"
