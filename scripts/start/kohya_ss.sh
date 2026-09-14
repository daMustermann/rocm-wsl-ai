#!/bin/bash
# ==============================================================================
# Start kohya_ss (LoRA / DreamBooth training GUI)
# ==============================================================================
# kohya_ss uses its own virtual environment (kohya_env) and its GUI entry point
# has moved between releases, so the script probes for it rather than assuming.
# ==============================================================================
set -uo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export TOOLKIT_ROOT
# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/lib/launch.sh"

ai_load_env >/dev/null 2>&1 || true

KOHYA_DIR="${KOHYA_DIR:-$HOME/kohya_ss}"
PORT="${KOHYA_PORT:-7861}"

# The GUI entry point has changed names across kohya_ss releases.
GUI_ENTRY=""
for candidate in kohya_gui.py gui.py setup/run_gui.py; do
    if [ -f "$KOHYA_DIR/$candidate" ]; then
        GUI_ENTRY="$candidate"
        break
    fi
done

if [ -z "$GUI_ENTRY" ]; then
    ai_err "kohya_ss GUI entry point not found in $KOHYA_DIR"
    ai_say "     Expected one of: kohya_gui.py, gui.py, setup/run_gui.py"
    ai_say "     Reinstall it:  ./menu.sh  ->  Install  ->  kohya_ss"
    exit 1
fi

ai_launch \
    --name "kohya_ss" \
    --dir "$KOHYA_DIR" \
    --command "python $GUI_ENTRY --listen 0.0.0.0 --server_port $PORT" \
    --venv "kohya_env" \
    --port "$PORT" \
    --allow-extra-args \
    -- "$@"
