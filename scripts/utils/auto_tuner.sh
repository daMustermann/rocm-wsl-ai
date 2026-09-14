#!/bin/bash
# ==============================================================================
# Performance Auto-Tuner (menu front-end for perf_engine.py)
# ==============================================================================
# The measurement, scoring and honest-verdict logic all live in
# scripts/utils/perf_engine.py. This script only drives the UI around it.
#
# What the previous version did, and why it was replaced:
#   It benchmarked 4096x4096 fp32 matmul + softmax four times and attributed the
#   differences to MIGRAPHX_MLIR_USE_SPECIFIC_OPS and PYTORCH_ALLOC_CONF.
#   Neither variable affects PyTorch's HIP backend (MIGRAPHX is a separate
#   runtime that torch does not use unless torch_migraphx is installed), so the
#   "winner" was noise. It also wrote ~/.genai_opt_profile, which the launch
#   scripts then sourced for every tool.
# ==============================================================================
set -uo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export TOOLKIT_ROOT
# common.sh provides choose()/confirm() and the colour constants; launch.sh
# provides the GPU environment and preflight. Both are required — launch.sh does
# not pull in common.sh.
# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/lib/common.sh"
# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/lib/launch.sh"

ENGINE="$TOOLKIT_ROOT/scripts/utils/perf_engine.py"
VENV_PY="$HOME/genai_env/bin/python3"

clear
ai_banner "Performance Auto-Tuner"

if [ ! -f "$ENGINE" ]; then
    ai_err "perf_engine.py not found at $ENGINE"
    read -rp "  Press Enter to return..."
    exit 1
fi

if [ ! -x "$VENV_PY" ]; then
    ai_err "The base environment is not installed (no ~/genai_env)."
    ai_say "     Install it first:  ./menu.sh  ->  Install  ->  Base Environment"
    echo ""
    read -rp "  Press Enter to return..."
    exit 1
fi

# --- Explain what is about to happen -----------------------------------------
cat <<'EOF'
  This measures several candidate configurations on YOUR GPU and keeps the one
  that actually wins. It runs short bursts of diffusion-shaped work
  (convolutions, attention, and a multi-step denoising loop) and compares them.

  It takes roughly 2-5 minutes. Do not start a game or another GPU workload
  while it runs — that makes the numbers unreliable, and the tuner will say so
  rather than guess.
EOF
echo ""

if ! ai_preflight; then
    echo ""
    ai_err "The GPU is not ready, so there is nothing to measure."
    read -rp "  Press Enter to return..."
    exit 1
fi

# --- Choose how thorough to be -----------------------------------------------
# Uses the toolkit's own choose(), not `gum choose`. gum's TUI needs stdout to be
# a terminal, and this value is captured, so gum cannot render and hangs forever
# with a blank screen — which is exactly what happened: a ten-minute wait at 0.6%
# CPU with no output and no benchmark ever starting.
MODE="standard"
CHOICE="$(choose "How thorough should the tuning be?" \
    "quick|Quick       - about 1 minute, fewer samples" \
    "standard|Standard    - about 3 minutes, recommended" \
    "thorough|Thorough    - about 8 minutes, best accuracy")" || {
    ai_info "Cancelled."
    exit 0
}
MODE="${CHOICE%%|*}"

case "$MODE" in
    quick)    ENGINE_FLAGS=(--quick) ;;
    thorough) ENGINE_FLAGS=(--iters 80 --warmup 8) ;;
    *)        ENGINE_FLAGS=() ; MODE="standard" ;;
esac

echo ""
ai_info "Starting the $MODE measurement run."
ai_dim  "  Candidates are measured in separate processes, so a bad one cannot"
ai_dim  "  take down the whole run."
ai_dim  "  Progress is printed below; the whole run takes a few minutes."
echo ""

# Run it unbuffered. Python block-buffers stdout whenever it is not a terminal,
# which would hold every progress line back until the process exits and leave the
# user staring at a frozen screen for minutes. -u and PYTHONUNBUFFERED together
# cover both this call and anything the engine spawns.
set +e
PYTHONUNBUFFERED=1 "$VENV_PY" -u "$ENGINE" bench --save-report "${ENGINE_FLAGS[@]}"
ENGINE_RC=$?
set -e

echo ""
case "$ENGINE_RC" in
    0)
        ai_ok "Tuning complete. The profile is now applied to every tool."
        ;;
    3)
        ai_err "No candidate produced a valid measurement."
        ai_say "     Usually this means another GPU workload was running, or the"
        ai_say "     GPU needs a restart (in PowerShell: wsl --shutdown)."
        ;;
    2)
        ai_err "The GPU was not visible to PyTorch."
        ai_say "     Run:  ./menu.sh  ->  Settings  ->  GPU Diagnostics"
        ;;
    *)
        ai_err "The tuner exited with code $ENGINE_RC."
        ai_say "     Full report (if produced): $ROCM_AI_CONFIG_DIR/last_benchmark.json"
        ;;
esac

# --- Show the resulting profile ----------------------------------------------
if [ "$ENGINE_RC" = "0" ]; then
    echo ""
    "$VENV_PY" "$ENGINE" show | sed 's/^/  /'
fi

echo ""
read -rp "  Press Enter to return to the menu..."
