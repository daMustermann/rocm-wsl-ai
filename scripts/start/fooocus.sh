#!/bin/bash
set -euo pipefail

# Get the script's directory and source the common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../lib/common.sh"

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
FOOOCUS_DIR="$HOME/Fooocus"

# --- Main Logic ---
headline "Starting Fooocus"

if [ ! -d "$FOOOCUS_DIR" ]; then
    err "Fooocus directory not found at $FOOOCUS_DIR"
    err "Please install it first via the main menu."
    exit 1
fi

if [ ! -f "$VENV_PATH/bin/activate" ]; then
    err "Python virtual environment not found at $VENV_PATH"
    err "Please run the base installation first."
    exit 1
fi

log "Activating Python virtual environment..."
# shellcheck disable=SC1091
source "$VENV_PATH/bin/activate"

log "Changing to Fooocus directory: $FOOOCUS_DIR"
cd "$FOOOCUS_DIR"

log "Launching Fooocus..."
python launch.py --listen 0.0.0.0 --port 7865

# Deactivate virtual environment on exit
trap 'deactivate' EXIT
success "Fooocus has been launched."
