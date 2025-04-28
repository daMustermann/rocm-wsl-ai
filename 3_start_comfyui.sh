#!/bin/bash

# ==============================================================================
# Script to easily start ComfyUI.
#
# Assumes ComfyUI was installed using the previous scripts in the default
# location (~/ComfyUI) and using the default virtual environment name
# (genai_env).
# ==============================================================================

# --- Configuration ---
# Name of the Python virtual environment
VENV_NAME="genai_env"
# Directory where ComfyUI was cloned
COMFYUI_DIR="$HOME/ComfyUI"

# --- Script Start ---
echo "Attempting to start ComfyUI..."
echo "---------------------------------"

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
echo "Launching ComfyUI..."
echo "(Run command: python main.py $@)"
echo "---------------------------------"
# "$@" passes all arguments given to this script directly to main.py
# Example: ./start_comfyui.sh --listen --port 8888
python main.py "$@"

# --- Script End ---
EXIT_CODE=$?
echo "---------------------------------"
echo "ComfyUI process finished with exit code: $EXIT_CODE"

# The virtual environment will deactivate automatically when the script exits
# or you can manually uncomment 'deactivate' if needed in specific scenarios.
# deactivate

exit $EXIT_CODE
