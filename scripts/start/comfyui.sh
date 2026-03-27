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

# Enable ROCDXG for WSL GPU compute
export HSA_ENABLE_DXG_DETECTION=1

# Display GPU information if available
if [ ! -z "$HSA_OVERRIDE_GFX_VERSION" ]; then
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
source "$ACTIVATE_SCRIPT"
# Optional: Verify which python is being used
# echo "Using Python: $(which python)"

# --- 3. Navigate to ComfyUI Directory ---
echo "Navigating to ComfyUI directory: ${COMFYUI_DIR}"
cd "$COMFYUI_DIR"

# --- 4. Launch ComfyUI ---
echo "Launching ComfyUI with Smart Sleep VRAM Manager..."
echo "Idle timeout is 30 minutes. The GPU will free up automatically."

# Load Auto-Tuned Magic Settings (if the user ran Auto-Tuner)
if [ -f "$HOME/.genai_opt_profile" ]; then 
    echo "[INFO] Loading Magic Settings from ~/.genai_opt_profile"
    source "$HOME/.genai_opt_profile"
fi

# Optimized parameters for ROCm
OPTIMIZED_PARAMS="--lowvram --disable-pinned-memory"

if [ -z "$MIGRAPHX_MLIR_USE_SPECIFIC_OPS" ]; then
    export MIGRAPHX_MLIR_USE_SPECIFIC_OPS="attention"
fi

# Detect custom port or default to 8188 for the wake server
PORT=8188
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
