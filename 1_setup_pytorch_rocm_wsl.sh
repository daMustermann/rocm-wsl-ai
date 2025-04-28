#!/bin/bash

# ==============================================================================
# Script to install AMD GPU drivers (ROCm), PyTorch, and Triton
# for generative AI (ComfyUI, SD.Next, etc.) on Ubuntu 24.04 LTS within WSL2.
#
# Target GPU: Radeon RX 7900 XTX (or other compatible RDNA3 GPUs)
# ROCm Version: Based on AMD's current recommendations for Ubuntu 24.04/WSL
# PyTorch Version: Stable version compatible with the installed ROCm
#
# Sources:
# - https://rocm.docs.amd.com/projects/radeon/en/latest/docs/install/wsl/install-radeon.html
# - https://rocm.docs.amd.com/projects/radeon/en/latest/docs/install/wsl/install-pytorch.html
# - https://pytorch.org/get-started/locally/
# ==============================================================================

# --- Configuration ---
# You can change the ROCm version components here if AMD updates recommendations
# Check the AMD docs link above for the latest installer URL/version if needed.
ROCM_INSTALLER_DEB_URL="https://repo.radeon.com/amdgpu-install/6.3.4/ubuntu/noble/amdgpu-install_6.3.60304-1_all.deb"
# Define the ROCm version string used for the PyTorch install URL (e.g., "6.3")
# This should match the major.minor version of the ROCm stack being installed.
PYTORCH_ROCM_VERSION="6.3"
# Python Virtual Environment Name
VENV_NAME="genai_env"

# --- Script Start ---
echo "Starting ROCm + PyTorch setup for WSL2 Ubuntu 24.04..."

# Exit immediately if a command exits with a non-zero status
set -e

# --- 1. System Update and Prerequisites ---
echo "[TASK 1/6] Updating system packages and installing prerequisites..."
sudo apt update
sudo apt upgrade -y
sudo apt install -y wget gpg build-essential git python3-pip python3-venv libnuma-dev pkg-config
echo "[TASK 1/6] System update and prerequisites installation complete."
echo "--------------------------------------------------"

# --- 2. Install ROCm for WSL ---
echo "[TASK 2/6] Installing ROCm stack for WSL..."

# Download the amdgpu-install script package
ROCM_INSTALLER_DEB_FILE=$(basename ${ROCM_INSTALLER_DEB_URL})
echo "Downloading ROCm installer script package: ${ROCM_INSTALLER_DEB_FILE}..."
wget -nv --show-progress ${ROCM_INSTALLER_DEB_URL}

# Install the package
echo "Installing ROCm installer script package..."
sudo apt install -y ./${ROCM_INSTALLER_DEB_FILE}

# Clean up downloaded deb file
rm ${ROCM_INSTALLER_DEB_FILE}

# Install ROCm packages using the WSL usecase (no kernel modules)
# This step can take a significant amount of time.
echo "Running amdgpu-install for WSL usecase (this may take several minutes)..."
sudo amdgpu-install -y --usecase=wsl,rocm --no-dkms

echo "[TASK 2/6] ROCm stack installation complete."
echo "--------------------------------------------------"

# --- 3. User Group Configuration ---
echo "[TASK 3/6] Configuring user groups..."
echo "Adding current user ($USER) to the 'render' and 'video' groups..."
sudo usermod -a -G render,video $LOGNAME

echo "[IMPORTANT] Group changes require a WSL restart to take effect."
echo "          Please run 'wsl --shutdown' in Windows PowerShell/CMD, then restart your Ubuntu terminal."
read -p "Press Enter to continue the script after you have restarted WSL, or Ctrl+C to exit and restart later..."

echo "[TASK 3/6] User group configuration step finished (pending WSL restart)."
echo "--------------------------------------------------"

# --- 4. Setup Python Virtual Environment ---
echo "[TASK 4/6] Setting up Python virtual environment '${VENV_NAME}'..."
# Check if directory exists, create if not
if [ ! -d "$HOME/$VENV_NAME" ]; then
    python3 -m venv "$HOME/$VENV_NAME"
    echo "Virtual environment created at $HOME/$VENV_NAME"
else
    echo "Virtual environment directory $HOME/$VENV_NAME already exists."
fi

# Activate the virtual environment for the rest of the script
source "$HOME/$VENV_NAME/bin/activate"

echo "Upgrading pip within the virtual environment..."
pip install --upgrade pip wheel

echo "[TASK 4/6] Python virtual environment setup complete. Environment activated."
echo "--------------------------------------------------"

# --- 5. Install PyTorch with ROCm Support & Triton ---
echo "[TASK 5/6] Installing PyTorch for ROCm ${PYTORCH_ROCM_VERSION} and Triton..."

# Construct the PyTorch installation command
# Check https://pytorch.org/get-started/locally/ for the latest stable command if needed.
PYTORCH_PIP_COMMAND="pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm${PYTORCH_ROCM_VERSION}"

echo "Running PyTorch installation command (this may take a while):"
echo "${PYTORCH_PIP_COMMAND}"
${PYTORCH_PIP_COMMAND}

# WSL Specific PyTorch Library Path Update (Important!)
# Ensures PyTorch uses the system's ROCm runtime installed earlier.
echo "Performing WSL-specific PyTorch library path update..."
LOCATION=$(pip show torch | grep Location | awk -F ": " '{print $2}')
TORCH_LIB_PATH="${LOCATION}/torch/lib"

if [ -d "${TORCH_LIB_PATH}" ]; then
    SYSTEM_HSA_LIB="/opt/rocm/lib/libhsa-runtime64.so.1"
    if [ -f "${SYSTEM_HSA_LIB}" ]; then
        echo "Removing potentially bundled HSA runtime from ${TORCH_LIB_PATH}..."
        rm -f ${TORCH_LIB_PATH}/libhsa-runtime64.so*
        echo "Creating symlink from system ROCm library (${SYSTEM_HSA_LIB}) to PyTorch directory..."
        ln -s "${SYSTEM_HSA_LIB}" "${TORCH_LIB_PATH}/"
        echo "Symlink created."
    else
        echo "[WARN] System HSA runtime library not found at ${SYSTEM_HSA_LIB}. Skipping WSL symlink step."
        echo "[WARN] This might cause issues if PyTorch bundles an incompatible version for WSL."
    fi
else
    echo "[WARN] Could not find torch library path: ${TORCH_LIB_PATH}. Skipping WSL library path update."
fi

# Install Triton (pre-release often needed for latest ROCm compatibility)
echo "Installing Triton (using pre-release flag)..."
pip install -U --pre triton

echo "[TASK 5/6] PyTorch and Triton installation complete."
echo "--------------------------------------------------"

# --- 6. Verification ---
echo "[TASK 6/6] Running verification checks..."

# Check ROCm installation
echo "Verifying ROCm installation (rocminfo)..."
if command -v rocminfo &> /dev/null; then
    rocminfo | grep -E 'Agent [0-9]+|Name:|Marketing Name:' | grep -A2 -B1 'Agent' | grep -v -E 'Host|CPU' || echo "[WARN] rocminfo did not list an AMD GPU Agent as expected."
else
    echo "[WARN] rocminfo command not found. ROCm installation might be incomplete."
fi
echo "---"

# Check PyTorch and GPU detection
echo "Verifying PyTorch ROCm integration..."
python3 -c '
import torch
import os
print(f"--- PyTorch Verification ---")
print(f"PyTorch Version: {torch.__version__}")
rocm_available = torch.cuda.is_available()
print(f"ROCm Available via torch.cuda.is_available(): {rocm_available}")
# Check if ROCm specific functions are present (HIP is the runtime)
print(f"Built with ROCm (HIP): {torch.version.hip is not None}")
if rocm_available:
    try:
        print(f"Detected GPU Count: {torch.cuda.device_count()}")
        print(f"Detected GPU Name [0]: {torch.cuda.get_device_name(0)}")
        # Check environment variable that might be needed by some tools
        print(f"HSA_OVERRIDE_GFX_VERSION set to: {os.environ.get("HSA_OVERRIDE_GFX_VERSION", "Not Set")}")
    except Exception as e:
        print(f"[WARN] Error during GPU detail retrieval: {e}")
else:
    print("[WARN] PyTorch does not detect a compatible ROCm device.")
print(f"---------------------------")
' || echo "[WARN] PyTorch verification script encountered an error."
echo "---"

# Check Triton (Basic Import)
echo "Verifying Triton installation (basic import)..."
python3 -c 'import triton; print(f"Triton Version: {triton.__version__}")' || echo "[WARN] Failed to import Triton."

echo "[TASK 6/6] Verification checks complete."
echo "--------------------------------------------------"

# --- Script End ---
echo ""
echo "[SUCCESS] ROCm + PyTorch + Triton installation script finished!"
echo ""
echo "[IMPORTANT REMINDER] If you haven't already, restart WSL ('wsl --shutdown' in Windows, then restart Ubuntu) for group changes ('render', 'video') to apply."
echo ""
echo "[NEXT STEPS]"
echo "1. Ensure WSL has been restarted if you saw the prompt during the script."
echo "2. Activate the virtual environment in new terminals BEFORE running AI apps:"
echo "   source ~/${VENV_NAME}/bin/activate"
echo "3. You can now proceed to install ComfyUI, SD.Next, etc., following their respective instructions WITHIN the activated environment."
echo "   They should now detect and utilize your AMD GPU via PyTorch/ROCm."
echo ""

# Deactivate environment for the current script session if needed
# deactivate # Uncomment if you want the script's terminal session to exit the venv

exit 0
