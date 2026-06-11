#!/bin/bash

# ==============================================================================
# Script to easily start ComfyUI.
#
# Assumes ComfyUI was installed using the previous scripts in the default
# location (~/ComfyUI) and using the default virtual environment name
# (genai_env).
# ==============================================================================

# --- Configuration ---
# Current script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Name of the Python virtual environment
VENV_NAME="genai_env"
# Directory where ComfyUI was cloned
COMFYUI_DIR="$HOME/ComfyUI"

# --- Script Start ---
echo "Attempting to start ComfyUI..."
echo "---------------------------------"

# Load persistent user settings (GPU profile, port overrides, etc.)
if [ -f "$HOME/.config/rocm-wsl-ai/user.env" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.config/rocm-wsl-ai/user.env"
fi
# Also load the auto-detected GPU environment (written by gpu_config.sh).
# This ensures HSA_OVERRIDE_GFX_VERSION is set even if user.env was never
# configured via the Settings menu.
if [ -f "$HOME/.config/rocm-wsl-ai/gpu.env" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.config/rocm-wsl-ai/gpu.env"
fi

# Enable ROCDXG for WSL GPU compute (user.env may already set this; ensure it's 1)
export HSA_ENABLE_DXG_DETECTION=1
# HSA_OVERRIDE_GFX_VERSION must NOT be set with ROCm 7.x + ROCDXG — DXCore detects
# the GPU architecture automatically. Setting it causes topology_sysfs_get_node_props
# to reject the value and the GPU becomes invisible to PyTorch.
if [ -f "/opt/rocm/lib/librocdxg.so" ]; then
    unset HSA_OVERRIDE_GFX_VERSION
fi

# Display GPU information if available
if [ -n "${HSA_OVERRIDE_GFX_VERSION:-}" ]; then
    echo "[INFO] Using GPU architecture: $HSA_OVERRIDE_GFX_VERSION"
fi

# --- 1. Define and Check Paths ---
VENV_PATH="$HOME/$VENV_NAME"
ACTIVATE_SCRIPT="$VENV_PATH/bin/activate"
COMFYUI_MAIN_SCRIPT="$COMFYUI_DIR/main.py"

# Check if virtual environment exists
if [ ! -f "$ACTIVATE_SCRIPT" ]; then
    echo "[ERROR] Virtual environment activation script not found at: $ACTIVATE_SCRIPT"
    echo "        Make sure the environment '${VENV_NAME}' was created successfully in your home directory."
    exit 1
fi

# Check if ComfyUI main script exists
if [ ! -f "$COMFYUI_MAIN_SCRIPT" ]; then
    echo "[ERROR] ComfyUI main script not found at: $COMFYUI_MAIN_SCRIPT"
    echo "        Make sure ComfyUI is cloned correctly in ${COMFYUI_DIR}."
    exit 1
fi

# --- 2. Activate Virtual Environment ---
echo "Activating Python environment: ${VENV_NAME}"
# shellcheck disable=SC1090
source "$ACTIVATE_SCRIPT"

# --- 2b. GPU Pre-flight check ---
# Run before launching ComfyUI so the user gets a clear fix hint instead of a Python traceback.
_gpu_preflight() {
    local ok=true

    # ROCDXG bridge check (WSL only)
    if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
        if [ ! -f "/opt/rocm/lib/librocdxg.so" ]; then
            echo ""
            echo "[ERROR] ROCDXG (librocdxg.so) is NOT installed."
            echo "        Without it ROCm cannot access the GPU inside WSL2."
            echo ""
            echo "  Fix: run the upgrade/install script:"
            echo "       bash ~/rocm-wsl-ai/scripts/install/upgrade_to_rocdxg.sh"
            echo ""
            ok=false
        fi
    fi

    # Quick PyTorch HIP check
    local hip_check
    hip_check=$(python3 -c "
import torch, sys
if not torch.cuda.is_available():
    print('FAIL')
    sys.exit(1)
print('OK')
" 2>/dev/null) || hip_check="FAIL"

    if [ "$hip_check" != "OK" ]; then
        echo ""
        echo "[ERROR] PyTorch cannot see any HIP/ROCm GPU."
        echo ""
        echo "  Common causes and fixes:"
        echo "  1. WSL was never restarted after ROCm install:"
        echo "       In Windows PowerShell: wsl --shutdown   then restart Ubuntu"
        echo "  2. ROCDXG not installed (see above)"
        echo "  3. HSA_ENABLE_DXG_DETECTION not set:"
        echo "       export HSA_ENABLE_DXG_DETECTION=1   (already done here — check user.env)"
        echo "  4. AMD Windows driver too old — requires Adrenalin 26.2.2 or newer"
        echo "  5. Run the GPU diagnostics for a full health check:"
        echo "       bash ~/rocm-wsl-ai/scripts/utils/gpu_diag.sh"
        echo ""
        ok=false
    fi

    if ! $ok; then
        echo "[ABORT] ComfyUI was NOT started. Resolve the issues above and try again."
        exit 1
    fi

    echo "[OK] GPU detected — proceeding to launch ComfyUI."
}
_gpu_preflight

# --- 3. Navigate to ComfyUI Directory ---
echo "Navigating to ComfyUI directory: ${COMFYUI_DIR}"
cd "$COMFYUI_DIR"

# --- 4. Launch ComfyUI ---
echo "Launching ComfyUI with Smart Sleep VRAM Manager..."
echo "Idle timeout is 30 minutes. The GPU will free up automatically."

# Load Auto-Tuned Magic Settings (if the user ran Auto-Tuner)
# Also auto-migrate the deprecated PYTORCH_HIP_ALLOC_CONF variable if it is still present.
if [ -f "$HOME/.genai_opt_profile" ]; then
    if grep -q "PYTORCH_HIP_ALLOC_CONF" "$HOME/.genai_opt_profile" 2>/dev/null; then
        sed -i 's/PYTORCH_HIP_ALLOC_CONF/PYTORCH_ALLOC_CONF/g' "$HOME/.genai_opt_profile"
        echo "[INFO] Auto-migrated ~/.genai_opt_profile: PYTORCH_HIP_ALLOC_CONF -> PYTORCH_ALLOC_CONF"
    fi
    echo "[INFO] Loading Magic Settings from ~/.genai_opt_profile"
    # shellcheck disable=SC1090
    source "$HOME/.genai_opt_profile"
fi

# Optimized parameters for ROCm
OPTIMIZED_PARAMS="--lowvram --disable-pinned-memory"

if [ -z "$MIGRAPHX_MLIR_USE_SPECIFIC_OPS" ]; then
    export MIGRAPHX_MLIR_USE_SPECIFIC_OPS="attention"
fi

# Detect custom port: prefer user.env override, then CLI --port arg, else default 8188
PORT="${COMFYUI_PORT:-8188}"
ARGS=("$@")
for ((i=0; i<${#ARGS[@]}; i++)); do
    if [ "${ARGS[$i]}" == "--port" ]; then
        PORT="${ARGS[$i+1]}"
    fi
done

# Start the execution loop for Smart Sleep
while true; do
    echo "---------------------------------"
    echo "Run command: python main.py $OPTIMIZED_PARAMS $@"
    
    # Run the Smart Sleep Wrapper
    python "$SCRIPT_DIR/../../scripts/utils/smart_sleep_wrapper.py" python main.py $OPTIMIZED_PARAMS "$@"
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 42 ]; then
        echo "---------------------------------"
        # Enter Wake Server mode
        python "$SCRIPT_DIR/../../scripts/utils/wake_server.py" "$PORT"
    else
        echo "---------------------------------"
        echo "ComfyUI process finished with exit code: $EXIT_CODE"
        break
    fi
done

exit $EXIT_CODE
