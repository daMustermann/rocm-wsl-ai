#!/bin/bash
# ==============================================================================
# Install kohya_ss (LoRA / DreamBooth / fine-tuning GUI)
# ==============================================================================
# Thin wrapper. The real implementation is lib/tools.sh::rocm_ai_install_tool,
# plus the kohya-specific details there (dedicated kohya_env virtualenv, the
# sd-scripts submodule, and matching the ROCm PyTorch build from ~/genai_env).
#
# Usage:
#   scripts/install/kohya_ss.sh
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/_shim.sh"

rocm_ai_shim_bootstrap "$SCRIPT_DIR"

standard_header "kohya_ss — LoRA and model training installation"

rocm_ai_shim_install "kohya_ss"
rc=$?

if [ "$rc" -eq 0 ]; then
    success "kohya_ss is ready."
    cat <<EOF

  Location : $(rocm_ai_tool_dir kohya_ss)
  Venv     : (dedicated) ~/kohya_env
  Launch   : ./menu.sh  ->  Launch  ->  kohya_ss (training)
             or: scripts/start/kohya_ss.sh
  Web UI   : http://localhost:$(rocm_ai_tool_effective_port kohya_ss)

  kohya_ss uses its own Python environment so that training dependencies cannot
  disturb your inference tools. Your ComfyUI and SD.Next installs are untouched.

EOF
fi
exit "$rc"
