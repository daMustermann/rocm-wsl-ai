#!/bin/bash
# ==============================================================================
# Start SD.Next
# ==============================================================================
# SD.Next performs its own ROCm detection and manages its own virtual
# environment through webui.sh. We provide the GPU environment and the tuned
# profile, then hand over.
#
# On precision flags:
#   The previous version always passed `--no-half --no-half-vae`. Those are
#   workarounds for specific AMD situations, and `--no-half` in particular forces
#   fp32 everywhere, which is a large slowdown on cards that handle bf16 well
#   (RDNA3 in particular has weak fp16 throughput relative to its fp32, so the
#   historical workarounds are easy to get backwards).
#   SD.Next's own defaults are now ROCm-aware, so this script passes only what
#   is required to select the ROCm backend and leaves precision to SD.Next.
#   If you see black or NaN images, add the workarounds yourself via
#   ~/.config/rocm-wsl-ai/user.env:
#       export SDNEXT_EXTRA_ARGS="--no-half-vae"
# ==============================================================================
set -uo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export TOOLKIT_ROOT
# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/lib/launch.sh"

ai_load_env >/dev/null 2>&1 || true

SDNEXT_DIR="${SDNEXT_DIR:-$HOME/SD.Next}"
PORT="${SDNEXT_PORT:-7860}"

if [ ! -f "$SDNEXT_DIR/webui.sh" ]; then
    ai_err "SD.Next is not installed (missing $SDNEXT_DIR/webui.sh)."
    ai_say "     Install it:  ./menu.sh  ->  Install  ->  SD.Next"
    exit 1
fi

# SD.Next manages its own venv, so no --venv here. The preflight still runs,
# because it is better to show the GPU fix checklist than a wall of Python.
ai_launch \
    --name "SD.Next" \
    --dir "$SDNEXT_DIR" \
    --command "./webui.sh --use-rocm --port $PORT ${SDNEXT_EXTRA_ARGS:-}" \
    --port "$PORT" \
    --allow-extra-args \
    -- "$@"
