#!/bin/bash

# ==============================================================================
# Start kohya_ss Training GUI
#
# Uses the dedicated kohya_env virtual environment. Starts the web-based GUI
# on http://localhost:7861 — open this in your Windows browser.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../lib/common.sh"

KOHYA_DIR="$HOME/kohya_ss"
KOHYA_VENV="$HOME/kohya_env"

headline "Starting kohya_ss Training GUI"

# Load persistent user settings (GPU profile, port overrides, etc.)
load_user_env 2>/dev/null || true

# Enable ROCDXG for WSL GPU compute
export HSA_ENABLE_DXG_DETECTION=1

# Validate installation
if [ ! -d "$KOHYA_DIR" ]; then
    err "kohya_ss not found at $KOHYA_DIR"
    err "Please install it first via: Main Menu → Install Tools → kohya_ss"
    exit 1
fi

if [ ! -f "$KOHYA_VENV/bin/activate" ]; then
    err "kohya_ss virtual environment not found at $KOHYA_VENV"
    err "Please reinstall kohya_ss via: Main Menu → Install Tools → kohya_ss"
    exit 1
fi

# shellcheck disable=SC1090
source "$KOHYA_VENV/bin/activate"
cd "$KOHYA_DIR"

# Load Auto-Tuned Magic Settings if available
if [ -f "$HOME/.genai_opt_profile" ]; then
    log "Loading Magic Settings from ~/.genai_opt_profile"
    # shellcheck disable=SC1091
    source "$HOME/.genai_opt_profile"
fi

# Detect GUI entry point (differs between kohya_ss versions)
GUI_SCRIPT=""
for candidate in kohya_gui.py gui.py; do
    if [ -f "$KOHYA_DIR/$candidate" ]; then
        GUI_SCRIPT="$candidate"
        break
    fi
done

if [ -z "$GUI_SCRIPT" ]; then
    err "No GUI entry point found in $KOHYA_DIR"
    err "Expected: kohya_gui.py  or  gui.py"
    deactivate
    exit 1
fi

PORT="${KOHYA_PORT:-7861}"
log "Launching $GUI_SCRIPT on port $PORT ..."
echo ""
echo "  Open in Windows browser: http://localhost:$PORT"
echo "  Press Ctrl+C to stop the server."
echo ""

python "$GUI_SCRIPT" --listen 0.0.0.0 --server_port "$PORT" "$@"

deactivate
