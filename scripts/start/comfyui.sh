#!/bin/bash
# ==============================================================================
# Start ComfyUI
# ==============================================================================
# All of the environment, tuning, flag validation and idle-hibernation logic
# lives in lib/launch.sh. This file only declares what is ComfyUI-specific.
#
# Performance note on the old version:
#   The previous script hardcoded `--lowvram --disable-pinned-memory`. On a card
#   with enough VRAM that is actively counterproductive — `--lowvram` puts
#   ComfyUI into VRAMState.LOW_VRAM, where the model is split into per-block
#   chunks that are loaded and freed around every sampling step. It was chosen
#   as a workaround for weak GPUs and applied to everyone.
#   Flags are now derived from the profile measured for this specific GPU.
# ==============================================================================
set -uo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export TOOLKIT_ROOT
# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/lib/launch.sh"

# Load the user's environment so port overrides are visible here.
ai_load_env >/dev/null 2>&1 || true

COMFYUI_DIR="${COMFYUI_DIR:-$HOME/ComfyUI}"
PORT="${COMFYUI_PORT:-8188}"

# Honour an explicit --port passed on the command line.
for ((i = 1; i <= $#; i++)); do
    if [ "${!i}" = "--port" ]; then
        j=$((i + 1))
        PORT="${!j:-$PORT}"
    fi
done

ai_launch \
    --name "ComfyUI" \
    --dir "$COMFYUI_DIR" \
    --command "python main.py --listen 127.0.0.1 --port $PORT ${COMFYUI_EXTRA_ARGS:-}" \
    --venv "genai_env" \
    --port "$PORT" \
    --tool-key "comfyui" \
    --allow-extra-args \
    -- "$@"

# ------------------------------------------------------------------------------
# Notes on ComfyUI 0.35 features this toolkit deliberately leaves at default
# ------------------------------------------------------------------------------
# --enable-triton-backend
#   ComfyUI 0.35 ships a comfy-kitchen Triton backend, off by default. It does
#   activate here with the AMD triton build ("Found triton 3.6.0+rocm7.2.4.
#   Enabling comfy-kitchen triton backend"), but comparing its reported capability
#   list against the HIP backend shows it adds nothing HIP does not already
#   provide, and no throughput measurement confirmed it is faster — the only
#   timings available were confounded by page cache. Left off rather than assumed
#   to help. To try it:
#       echo 'export COMFYUI_EXTRA_ARGS="--enable-triton-backend"' \
#           >> ~/.config/rocm-wsl-ai/user.env
#   then compare your own prompt times.
#
# --async-offload, --fast-disk, --cache-ram, --disable-cuda-graphs
#   Present in 0.35 and all left at their defaults, which measured well in the
#   tuner on this hardware. Async weight offloading is already enabled by default
#   for AMD GPUs.
#
# If you change any of these, re-run Performance -> Auto-tune afterwards: the
# tuning profile was measured with the defaults in place.
# ------------------------------------------------------------------------------
