#!/bin/bash
# ==============================================================================
# Start Text Generation WebUI (LLM chat / text generation)
# ==============================================================================
set -uo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export TOOLKIT_ROOT
# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/lib/launch.sh"

ai_load_env >/dev/null 2>&1 || true

TEXTGEN_DIR="${TEXTGEN_DIR:-$HOME/text-generation-webui}"
PORT="${TEXTGEN_PORT:-5000}"

# Newer releases renamed start_linux.sh's python entry point to server.py; older
# ones used server.py too, but some forks still ship webui.py.
ENTRY=""
for candidate in server.py webui.py; do
    if [ -f "$TEXTGEN_DIR/$candidate" ]; then
        ENTRY="$candidate"
        break
    fi
done

if [ -z "$ENTRY" ]; then
    ai_err "Text Generation WebUI not found in $TEXTGEN_DIR"
    ai_say "     Install it:  ./menu.sh  ->  Install  ->  Text Generation WebUI"
    exit 1
fi

ai_launch \
    --name "Text Generation WebUI" \
    --dir "$TEXTGEN_DIR" \
    --command "python $ENTRY --listen --api --port $PORT --trust-remote-code" \
    --venv "genai_env" \
    --port "$PORT" \
    --allow-extra-args \
    -- "$@"
