#!/bin/bash
set -euo pipefail

# Get the script's directory and source the common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../lib/common.sh"

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
FORGE_DIR="$HOME/stable-diffusion-webui-forge"

# --- Main Logic ---
headline "Starting SD WebUI Forge"

if [ ! -d "$FORGE_DIR" ]; then
    err "Forge directory not found at $FORGE_DIR"
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

log "Changing to Forge directory: $FORGE_DIR"
cd "$FORGE_DIR"

log "Launching Forge with ROCm arguments..."
./webui.sh --use-rocm

# Deactivate virtual environment on exit
trap 'deactivate' EXIT
success "Forge has been launched."
