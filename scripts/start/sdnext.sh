#!/bin/bash
set -euo pipefail

# Get the script's directory and source the common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../lib/common.sh"

# --- Configuration ---
# Name of the Python virtual environment
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
SDNEXT_DIR="$HOME/SD.Next"

# Enable ROCDXG for WSL GPU compute
export HSA_ENABLE_DXG_DETECTION=1

# --- Main Logic ---
headline "Starting SD.Next"

if [ ! -f "$SDNEXT_DIR/webui.sh" ]; then
    err "SD.Next not found at $SDNEXT_DIR"
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

log "Changing to SD.Next directory: $SDNEXT_DIR"
cd "$SDNEXT_DIR"

log "Launching SD.Next with ROCm arguments..."
./webui.sh --use-rocm --skip-torch-cuda-test --no-half --no-half-vae

# Deactivate virtual environment on exit
trap 'deactivate' EXIT
success "SD.Next has been launched."
