#!/bin/bash

# ==============================================================================
# Script to install SD.Next for AMD GPUs using ROCm in WSL2 Ubuntu 24.04.
#
# Assumes ROCm and PyTorch have been installed using the previous scripts.
# ==============================================================================

# --- Configuration ---
# Name of the Python virtual environment created by the previous script
VENV_NAME="genai_env"
# Directory where SD.Next will be cloned
SDNEXT_DIR="$HOME/SD.Next"

SCRIPT_DIR="$(dirname "$0")"
COMMON="$SCRIPT_DIR/common.sh"
[ -f "$COMMON" ] && source "$COMMON" || { echo "common.sh not found"; exit 1; }

# --- Script Start ---
echo "Starting SD.Next installation..."
echo "---------------------------------"

# Exit immediately if a command exits with a non-zero status
set -e

# --- 1. Define and Check Paths ---
VENV_PATH="$HOME/$VENV_NAME"
ACTIVATE_SCRIPT="$VENV_PATH/bin/activate"

# Check if virtual environment exists
if [ ! -f "$ACTIVATE_SCRIPT" ]; then
    echo "[ERROR] Virtual environment activation script not found at: $ACTIVATE_SCRIPT"
    echo "        Make sure the environment '${VENV_NAME}' was created successfully in your home directory."
    echo "        Run the 1_setup_pytorch_rocm_wsl.sh script first."
    exit 1
fi

# --- 2. Activate Virtual Environment ---
echo "[TASK 1/4] Activating Python environment: ${VENV_NAME}"
source "$ACTIVATE_SCRIPT"
# Verify which python is being used
echo "Using Python: $(which python)"
echo "Python version: $(python --version)"
echo "Pip version: $(pip --version)"
echo "--------------------------------------------------"

# --- 3. Check for ROCm and PyTorch ---
echo "[TASK 2/4] Verifying ROCm and PyTorch installation..."

# Check if ROCm is installed
if command -v rocminfo &> /dev/null; then
    echo "ROCm is installed. Checking for GPU..."
    rocminfo | grep -E 'Agent [0-9]+|Name:|Marketing Name:' | grep -A2 -B1 'Agent' | grep -v -E 'Host|CPU' || echo "[WARN] rocminfo did not list an AMD GPU Agent as expected."
else
    echo "[ERROR] ROCm is not installed. Please run the 1_setup_pytorch_rocm_wsl.sh script first."
    exit 1
fi

# Check if PyTorch with ROCm support is installed
python -c "
import torch
print(f'PyTorch Version: {torch.__version__}')
rocm_available = torch.cuda.is_available()
print(f'ROCm Available via torch.cuda.is_available(): {rocm_available}')
if not rocm_available:
    print('[ERROR] PyTorch does not detect a compatible ROCm device.')
    exit(1)
else:
    print(f'Detected GPU Count: {torch.cuda.device_count()}')
    print(f'Detected GPU Name [0]: {torch.cuda.get_device_name(0)}')
    print(f'HSA_OVERRIDE_GFX_VERSION set to: {torch.version.hip}')
"
echo "--------------------------------------------------"

# --- 4. Clone or update SD.Next Repository ---
echo "[TASK 3/4] Ensuring SD.Next repository is present and up-to-date..."
if [ -d "$SDNEXT_DIR/.git" ]; then
    log "Updating existing SD.Next repository at ${SDNEXT_DIR}"
    git -C "$SDNEXT_DIR" pull --rebase --autostash || warn "Failed to pull latest SD.Next"
else
    log "Cloning SD.Next from upstream into ${SDNEXT_DIR}"
    git clone https://github.com/vladmandic/sdnext.git "$SDNEXT_DIR" || { echo "[ERROR] Failed to clone SD.Next"; exit 1; }
fi
echo "--------------------------------------------------"

# --- 5. Install / Upgrade SD.Next dependencies ---
echo "[TASK 4/4] Installing / upgrading SD.Next dependencies"
cd "$SDNEXT_DIR"
# Use toolkit venv to upgrade requirements if present
if ensure_venv "$VENV_NAME" ; then
    if [ -f requirements.txt ]; then
        pip install -r requirements.txt --upgrade || warn "Failed to install SD.Next requirements"
    else
        warn "No requirements.txt found for SD.Next"
    fi
else
    warn "Toolkit virtualenv not found at $VENV_PATH; please activate your environment and run manual upgrade if necessary"
fi

# Run a non-destructive quick test if available
if [ -x ./webui.sh ]; then
    log "Performing quick SD.Next launch test (no model download)"
    ./webui.sh --use-rocm --skip-torch-cuda-test --no-download-sd-model --no-half --no-half-vae --test || warn "SD.Next quick test failed (may be expected on first run)"
else
    warn "webui.sh not present or not executable"
fi
echo "--------------------------------------------------"

# --- Script End ---
echo ""
echo "[SUCCESS] SD.Next installation script finished!"
echo ""
echo "[HOW TO RUN SD.NEXT]"
echo "1. Open a new terminal or use the current one."
echo "2. Activate the virtual environment:"
echo "   source ~/${VENV_NAME}/bin/activate"
echo "3. Navigate to the SD.Next directory:"
echo "   cd ${SDNEXT_DIR}"
echo "4. Run SD.Next with ROCm support:"
echo "   ./webui.sh --use-rocm"
echo ""
echo "[IMPORTANT NOTES]"
echo "* You MUST activate the '${VENV_NAME}' environment every time before running SD.Next."
echo "* The first run will download models and may take some time."
echo "* You can add additional flags like:"
echo "  --listen                   (to access from other devices on your network)"
echo "  --port 7860                (to specify a different port)"
echo "  --no-half                  (if you encounter precision issues)"
echo "  --skip-torch-cuda-test     (to skip CUDA tests since we're using ROCm)"
echo ""
echo "* After starting, access the web interface at: http://localhost:7860"
echo ""

# The virtual environment remains active in the current terminal session
# unless you manually type 'deactivate'.

exit 0
