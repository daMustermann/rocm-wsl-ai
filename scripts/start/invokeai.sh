#!/bin/bash
set -euo pipefail

# Get the script's directory and source the common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../lib/common.sh"

# --- Configuration ---
INVOKEAI_DIR="$HOME/InvokeAI"

# --- Main Logic ---
headline "Starting InvokeAI"

if [ ! -f "$INVOKEAI_DIR/invoke.sh" ] && [ ! -f "$INVOKEAI_DIR/invoke.bat" ]; then
    err "InvokeAI not found at $INVOKEAI_DIR"
    err "Please install it first via the main menu."
    exit 1
fi

log "Changing to InvokeAI directory: $INVOKEAI_DIR"
cd "$INVOKEAI_DIR"

log "Launching InvokeAI..."
# InvokeAI has its own environment management, so we just run its script.
./invoke.sh

success "InvokeAI has been launched."
