#!/bin/bash
set -euo pipefail

# Get the script's directory and source the common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../lib/common.sh"

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
AUTOMATIC1111_DIR="$HOME/stable-diffusion-webui"

# --- Main Logic ---
headline "Starting Automatic1111 SD-WebUI"

if [ ! -f "$AUTOMATIC1111_DIR/webui.sh" ]; then
    err "Automatic1111 not found at $AUTOMATIC1111_DIR"
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

log "Changing to Automatic1111 directory: $AUTOMATIC1111_DIR"
cd "$AUTOMATIC1111_DIR"

# Check for the custom ROCm launch script, otherwise use the standard one
LAUNCH_SCRIPT="./webui.sh"
if [ -f "./launch_webui_rocm.sh" ]; then
    LAUNCH_SCRIPT="./launch_webui_rocm.sh"
    log "Found custom ROCm launch script."
fi

log "Launching Automatic1111..."
COMMAND_LINE_ARGS="--listen --enable-insecure-extension-access --theme dark --no-half-vae"
export COMMAND_LINE_ARGS
$LAUNCH_SCRIPT

# Deactivate virtual environment on exit
trap 'deactivate' EXIT
success "Automatic1111 has been launched."
