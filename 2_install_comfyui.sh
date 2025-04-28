#!/bin/bash

# ==============================================================================
# Script to install ComfyUI within the previously created ROCm/PyTorch venv.
#
# Assumes the 'setup_pytorch_rocm_wsl.sh' script ran successfully.
# ==============================================================================

# --- Configuration ---
# Name of the Python virtual environment created by the previous script
VENV_NAME="genai_env"
# Directory where ComfyUI will be cloned
COMFYUI_DIR="$HOME/ComfyUI"

# --- Script Start ---
echo "Starting ComfyUI installation..."

# Exit immediately if a command exits with a non-zero status
set -e

# --- 1. Activate Virtual Environment ---
echo "[TASK 1/3] Activating Python virtual environment '${VENV_NAME}'..."
VENV_PATH="$HOME/$VENV_NAME"
ACTIVATE_SCRIPT="$VENV_PATH/bin/activate"

if [ -f "$ACTIVATE_SCRIPT" ]; then
    source "$ACTIVATE_SCRIPT"
    echo "Virtual environment activated."
    echo "Using Python from: $(which python)"
    echo "Using pip from: $(which pip)"
else
    echo "[ERROR] Virtual environment activation script not found at: $ACTIVATE_SCRIPT"
    echo "        Please ensure the previous setup script ran successfully and the environment '$VENV_NAME' exists in your home directory."
    exit 1
fi
echo "--------------------------------------------------"

# --- 2. Clone ComfyUI Repository ---
echo "[TASK 2/3] Cloning ComfyUI repository..."

if [ ! -d "$COMFYUI_DIR" ]; then
    echo "Cloning ComfyUI from GitHub into ${COMFYUI_DIR}..."
    # Use the official ComfyUI repository URL
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
    echo "ComfyUI repository cloned successfully."
else
    echo "ComfyUI directory already exists at ${COMFYUI_DIR}. Skipping clone."
    echo "You can update ComfyUI later by navigating into the directory ('cd ${COMFYUI_DIR}') and running 'git pull'."
fi
echo "--------------------------------------------------"

# --- 3. Install ComfyUI Dependencies ---
echo "[TASK 3/3] Installing ComfyUI Python dependencies..."

# Navigate into the ComfyUI directory
cd "$COMFYUI_DIR"
echo "Changed directory to: $(pwd)"

# Check if requirements.txt exists
if [ -f "requirements.txt" ]; then
    echo "Installing dependencies using pip from requirements.txt..."
    echo "This might take a few minutes. It will use the PyTorch version already installed in your environment."
    # Use --no-cache-dir sometimes helps with pip issues in restricted environments or WSL
    pip install --no-cache-dir -r requirements.txt
    echo "ComfyUI dependencies installed successfully."
else
    echo "[ERROR] requirements.txt not found in ${COMFYUI_DIR}."
    echo "        Cloning might have failed, the repository structure might have changed, or you are not in the correct directory."
    # Attempt to change back to home directory before exiting
    cd "$HOME"
    exit 1
fi

# Navigate back to home directory (optional)
cd "$HOME"
echo "--------------------------------------------------"

# --- Script End ---
echo ""
echo "[SUCCESS] ComfyUI installation script finished!"
echo ""
echo "[HOW TO RUN COMFYUI]"
echo "1. Open a new terminal or use the current one."
echo "2. Activate the virtual environment:"
echo "   source ~/${VENV_NAME}/bin/activate"
echo "3. Navigate to the ComfyUI directory:"
echo "   cd ${COMFYUI_DIR}"
echo "4. Run ComfyUI:"
echo "   python main.py"
echo ""
echo "[IMPORTANT NOTES]"
echo "* You MUST activate the '${VENV_NAME}' environment every time before running ComfyUI."
echo "* You will need to download AI models (Stable Diffusion checkpoints, VAEs, LoRAs, ControlNets, etc.)"
echo "    and place them into the corresponding subdirectories within '${COMFYUI_DIR}/models/'."
echo "* Check the ComfyUI documentation/repository for more details on models and usage."
echo ""

# The virtual environment remains active in the current terminal session
# unless you manually type 'deactivate'.

exit 0
