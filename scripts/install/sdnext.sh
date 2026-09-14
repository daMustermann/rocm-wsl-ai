#!/bin/bash
# ==============================================================================
# Install SD.Next
# ==============================================================================
# Thin wrapper. The real implementation is lib/tools.sh::rocm_ai_install_tool,
# which is also what the menu uses — so installing from here and installing from
# the menu cannot drift apart.
#
# Usage:
#   scripts/install/sdnext.sh
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/_shim.sh"

rocm_ai_shim_bootstrap "$SCRIPT_DIR"

standard_header "SD.Next — installation"

rocm_ai_shim_install "sdnext"
rc=$?

if [ "$rc" -eq 0 ]; then
    success "SD.Next is ready."
    cat <<EOF

  Launch : ./menu.sh  ->  Launch  ->  SD.Next
           or: scripts/start/sdnext.sh
  Models : $(rocm_ai_tool_dir sdnext)/models/
  Web UI : http://localhost:$(rocm_ai_tool_effective_port sdnext)

  SD.Next manages its own Python environment and performs its own ROCm
  detection. The toolkit supplies the GPU environment and the tuned profile.

EOF
fi
exit "$rc"
