#!/bin/bash
# ==============================================================================
# Install ComfyUI
# ==============================================================================
# Thin wrapper. The real implementation is lib/tools.sh::rocm_ai_install_tool,
# which is also what the menu uses — so installing from here and installing from
# the menu cannot drift apart.
#
# Usage:
#   scripts/install/comfyui.sh
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/_shim.sh"

rocm_ai_shim_bootstrap "$SCRIPT_DIR"

standard_header "ComfyUI — installation"

rocm_ai_shim_install "comfyui"
rc=$?

if [ "$rc" -eq 0 ]; then
    success "ComfyUI is ready."
    cat <<EOF

  Launch : ./menu.sh  ->  Launch  ->  ComfyUI
           or: scripts/start/comfyui.sh
  Models : $(rocm_ai_tool_dir comfyui)/models/
  Web UI : http://localhost:$(rocm_ai_tool_effective_port comfyui)

EOF
fi
exit "$rc"
