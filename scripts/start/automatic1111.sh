#!/bin/bash
# ==============================================================================
# Start Automatic1111 (stable-diffusion-webui)
# ==============================================================================
# A1111's own webui.sh creates and manages its virtual environment, and its
# `launch.py` re-installs torch if it thinks it is missing — which on ROCm can
# replace the ROCm build with a CUDA one. The tuned environment (and the
# PYTORCH_ROCM_ARCH / HSA settings from lib/launch.sh) is what keeps it honest.
# ==============================================================================
set -uo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export TOOLKIT_ROOT
# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/lib/launch.sh"

ai_load_env >/dev/null 2>&1 || true

A1111_DIR="${A1111_DIR:-$HOME/stable-diffusion-webui}"
PORT="${A1111_PORT:-7860}"

if [ ! -f "$A1111_DIR/webui.sh" ]; then
    ai_err "Automatic1111 is not installed (missing $A1111_DIR/webui.sh)."
    ai_say "     Install it:  ./menu.sh  ->  Install  ->  Automatic1111"
    exit 1
fi

# The community ROCm launcher takes precedence when present.
LAUNCHER="./webui.sh"
if [ -f "$A1111_DIR/launch_webui_rocm.sh" ]; then
    LAUNCHER="./launch_webui_rocm.sh"
fi

ai_launch \
    --name "Automatic1111" \
    --dir "$A1111_DIR" \
    --command "$LAUNCHER --skip-torch-cuda-test --skip-version-check --port $PORT ${A1111_EXTRA_ARGS:-}" \
    --port "$PORT" \
    --allow-extra-args \
    -- "$@"
