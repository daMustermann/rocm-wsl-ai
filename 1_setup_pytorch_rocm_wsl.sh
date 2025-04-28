#!/bin/bash

# ==============================================================================
# Script to install AMD GPU drivers (ROCm), PyTorch, and Triton
# for generative AI (ComfyUI, SD.Next, etc.) on Ubuntu 24.04 LTS within WSL2.
#
# Auto-detects AMD GPU and applies appropriate configurations
# ROCm Version: Based on AMD's current recommendations for Ubuntu 24.04/WSL
# PyTorch Version: Stable version compatible with the installed ROCm
#
# Sources:
# - https://rocm.docs.amd.com/projects/radeon/en/latest/docs/install/wsl/install-radeon.html
# - https://rocm.docs.amd.com/projects/radeon/en/latest/docs/install/wsl/install-pytorch.html
# - https://pytorch.org/get-started/locally/
# ==============================================================================

# --- Configuration ---
# Python Virtual Environment Name
VENV_NAME="genai_env"

# --- GPU Detection and Configuration ---
# You can change the ROCm version components here if AMD updates recommendations
# Check the AMD docs link above for the latest installer URL/version if needed.
ROCM_INSTALLER_DEB_URL="https://repo.radeon.com/amdgpu-install/6.3.4/ubuntu/noble/amdgpu-install_6.3.60304-1_all.deb"
# Define the ROCm version string used for the PyTorch install URL (e.g., "6.3")
# This should match the major.minor version of the ROCm stack being installed.
PYTORCH_ROCM_VERSION="6.3"

# Default HSA_OVERRIDE_GFX_VERSION (will be set based on detected GPU)
HSA_OVERRIDE_GFX_VERSION=""

# --- Script Start ---
echo "Starting ROCm + PyTorch setup for WSL2 Ubuntu 24.04..."

# Exit immediately if a command exits with a non-zero status
set -e

# --- GPU Detection ---
echo "[INFO] Detecting AMD GPU..."

# First, check if we're in WSL
if grep -q Microsoft /proc/version; then
    echo "[INFO] Running in Windows Subsystem for Linux (WSL)"

    # In WSL, we need to get the GPU info from Windows
    # Install PowerShell if not already installed
    if ! command -v pwsh &> /dev/null; then
        echo "[INFO] Installing PowerShell to detect Windows GPU..."
        sudo apt-get update
        sudo apt-get install -y wget apt-transport-https software-properties-common
        wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
        sudo dpkg -i packages-microsoft-prod.deb
        rm packages-microsoft-prod.deb
        sudo apt-get update
        sudo apt-get install -y powershell
    fi

    # Use PowerShell to get GPU info from Windows
    GPU_INFO=$(pwsh -Command "Get-CimInstance -ClassName Win32_VideoController | Where-Object { \$_.Name -like '*Radeon*' -or \$_.Name -like '*AMD*' } | Select-Object -ExpandProperty Name")

    if [ -z "$GPU_INFO" ]; then
        echo "[WARNING] No AMD GPU detected in Windows. This script is intended for AMD GPUs."
        echo "[WARNING] Continuing with default settings, but ROCm may not work correctly."
    else
        echo "[INFO] Detected AMD GPU: $GPU_INFO"
    fi
else
    # Direct Linux detection
    if command -v lspci &> /dev/null; then
        GPU_INFO=$(lspci | grep -i 'vga\|3d\|display' | grep -i 'amd\|radeon\|ati')
        if [ -z "$GPU_INFO" ]; then
            echo "[WARNING] No AMD GPU detected. This script is intended for AMD GPUs."
            echo "[WARNING] Continuing with default settings, but ROCm may not work correctly."
        else
            echo "[INFO] Detected AMD GPU: $GPU_INFO"
        fi
    else
        echo "[WARNING] lspci command not found. Cannot detect GPU directly."
        echo "[WARNING] Continuing with default settings, but ROCm may not work correctly."
    fi
fi

# --- GPU Architecture Detection and Configuration ---
# Extract GPU model information from the detected GPU
if [ ! -z "$GPU_INFO" ]; then
    # Check for RDNA3 GPUs (RX 7000 series)
    if [[ "$GPU_INFO" =~ RX[[:space:]]*7[0-9]{3} ]] || [[ "$GPU_INFO" =~ Radeon[[:space:]]*7[0-9]{3} ]]; then
        echo "[INFO] Detected RDNA3 GPU (RX 7000 series)"
        # gfx1100 for Navi31 (RX 7900 XTX, 7900 XT)
        # gfx1101 for Navi32 (RX 7800 XT, 7700 XT)
        # gfx1102 for Navi33 (RX 7600, 7600 XT)
        if [[ "$GPU_INFO" =~ 79[0-9]{2} ]]; then
            HSA_OVERRIDE_GFX_VERSION="gfx1100"
            echo "[INFO] Setting HSA_OVERRIDE_GFX_VERSION=gfx1100 for Navi31 GPU"
        elif [[ "$GPU_INFO" =~ 78[0-9]{2} ]] || [[ "$GPU_INFO" =~ 77[0-9]{2} ]]; then
            HSA_OVERRIDE_GFX_VERSION="gfx1101"
            echo "[INFO] Setting HSA_OVERRIDE_GFX_VERSION=gfx1101 for Navi32 GPU"
        elif [[ "$GPU_INFO" =~ 76[0-9]{2} ]]; then
            HSA_OVERRIDE_GFX_VERSION="gfx1102"
            echo "[INFO] Setting HSA_OVERRIDE_GFX_VERSION=gfx1102 for Navi33 GPU"
        else
            HSA_OVERRIDE_GFX_VERSION="gfx1100"
            echo "[INFO] Setting default HSA_OVERRIDE_GFX_VERSION=gfx1100 for RDNA3 GPU"
        fi
    # Check for RDNA2 GPUs (RX 6000 series)
    elif [[ "$GPU_INFO" =~ RX[[:space:]]*6[0-9]{3} ]] || [[ "$GPU_INFO" =~ Radeon[[:space:]]*6[0-9]{3} ]]; then
        echo "[INFO] Detected RDNA2 GPU (RX 6000 series)"
        # gfx1030 for Navi21 (RX 6900 XT, 6800 XT, 6800)
        # gfx1031 for Navi22 (RX 6700 XT, 6700)
        # gfx1032 for Navi23 (RX 6600 XT, 6600)
        # gfx1034 for Navi24 (RX 6500 XT, 6400)
        if [[ "$GPU_INFO" =~ 69[0-9]{2} ]] || [[ "$GPU_INFO" =~ 68[0-9]{2} ]]; then
            HSA_OVERRIDE_GFX_VERSION="gfx1030"
            echo "[INFO] Setting HSA_OVERRIDE_GFX_VERSION=gfx1030 for Navi21 GPU"
        elif [[ "$GPU_INFO" =~ 67[0-9]{2} ]]; then
            HSA_OVERRIDE_GFX_VERSION="gfx1031"
            echo "[INFO] Setting HSA_OVERRIDE_GFX_VERSION=gfx1031 for Navi22 GPU"
        elif [[ "$GPU_INFO" =~ 66[0-9]{2} ]]; then
            HSA_OVERRIDE_GFX_VERSION="gfx1032"
            echo "[INFO] Setting HSA_OVERRIDE_GFX_VERSION=gfx1032 for Navi23 GPU"
        elif [[ "$GPU_INFO" =~ 65[0-9]{2} ]] || [[ "$GPU_INFO" =~ 64[0-9]{2} ]]; then
            HSA_OVERRIDE_GFX_VERSION="gfx1034"
            echo "[INFO] Setting HSA_OVERRIDE_GFX_VERSION=gfx1034 for Navi24 GPU"
        else
            HSA_OVERRIDE_GFX_VERSION="gfx1030"
            echo "[INFO] Setting default HSA_OVERRIDE_GFX_VERSION=gfx1030 for RDNA2 GPU"
        fi
    # Check for RDNA1 GPUs (RX 5000 series)
    elif [[ "$GPU_INFO" =~ RX[[:space:]]*5[0-9]{3} ]] || [[ "$GPU_INFO" =~ Radeon[[:space:]]*5[0-9]{3} ]]; then
        echo "[INFO] Detected RDNA1 GPU (RX 5000 series)"
        # gfx1010 for Navi10 (RX 5700 XT, 5700, 5600 XT)
        # gfx1011 for Navi12
        # gfx1012 for Navi14 (RX 5500 XT, 5500)
        if [[ "$GPU_INFO" =~ 57[0-9]{2} ]] || [[ "$GPU_INFO" =~ 56[0-9]{2} ]]; then
            HSA_OVERRIDE_GFX_VERSION="gfx1010"
            echo "[INFO] Setting HSA_OVERRIDE_GFX_VERSION=gfx1010 for Navi10 GPU"
        elif [[ "$GPU_INFO" =~ 55[0-9]{2} ]] || [[ "$GPU_INFO" =~ 54[0-9]{2} ]]; then
            HSA_OVERRIDE_GFX_VERSION="gfx1012"
            echo "[INFO] Setting HSA_OVERRIDE_GFX_VERSION=gfx1012 for Navi14 GPU"
        else
            HSA_OVERRIDE_GFX_VERSION="gfx1010"
            echo "[INFO] Setting default HSA_OVERRIDE_GFX_VERSION=gfx1010 for RDNA1 GPU"
        fi
    # Check for Vega GPUs
    elif [[ "$GPU_INFO" =~ Vega ]] || [[ "$GPU_INFO" =~ Radeon[[:space:]]VII ]]; then
        echo "[INFO] Detected Vega GPU"
        if [[ "$GPU_INFO" =~ Radeon[[:space:]]VII ]]; then
            HSA_OVERRIDE_GFX_VERSION="gfx906"
            echo "[INFO] Setting HSA_OVERRIDE_GFX_VERSION=gfx906 for Radeon VII"
        else
            HSA_OVERRIDE_GFX_VERSION="gfx900"
            echo "[INFO] Setting HSA_OVERRIDE_GFX_VERSION=gfx900 for Vega GPU"
        fi
    # Check for Polaris GPUs (RX 500/400 series)
    elif [[ "$GPU_INFO" =~ RX[[:space:]]*[54][0-9]{2} ]] || [[ "$GPU_INFO" =~ Radeon[[:space:]]*[54][0-9]{2} ]]; then
        echo "[INFO] Detected Polaris GPU (RX 500/400 series)"
        HSA_OVERRIDE_GFX_VERSION="gfx803"
        echo "[INFO] Setting HSA_OVERRIDE_GFX_VERSION=gfx803 for Polaris GPU"
    else
        echo "[WARNING] Could not determine specific AMD GPU architecture."
        echo "[WARNING] Using default configuration for RDNA3 GPUs."
        HSA_OVERRIDE_GFX_VERSION="gfx1100"
        echo "[INFO] Setting default HSA_OVERRIDE_GFX_VERSION=gfx1100"
    fi
else
    echo "[WARNING] No AMD GPU detected, using default configuration for RDNA3 GPUs."
    HSA_OVERRIDE_GFX_VERSION="gfx1100"
    echo "[INFO] Setting default HSA_OVERRIDE_GFX_VERSION=gfx1100"
fi

# Export HSA_OVERRIDE_GFX_VERSION for use in the script
export HSA_OVERRIDE_GFX_VERSION
echo "[INFO] GPU detection complete. Proceeding with installation..."

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

# Set HSA_OVERRIDE_GFX_VERSION in the environment
if [ ! -z "$HSA_OVERRIDE_GFX_VERSION" ]; then
    echo "export HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}" >> "$HOME/$VENV_NAME/bin/activate"
    echo "[INFO] Added HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION} to virtual environment activation script"
fi

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
python3 -c "
import torch
import os
print(f'--- PyTorch Verification ---')
print(f'PyTorch Version: {torch.__version__}')
rocm_available = torch.cuda.is_available()
print(f'ROCm Available via torch.cuda.is_available(): {rocm_available}')
# Check if ROCm specific functions are present (HIP is the runtime)
print(f'Built with ROCm (HIP): {torch.version.hip is not None}')
if rocm_available:
    try:
        print(f'Detected GPU Count: {torch.cuda.device_count()}')
        print(f'Detected GPU Name [0]: {torch.cuda.get_device_name(0)}')
        # Check environment variable that might be needed by some tools
        hsa_override = os.environ.get('HSA_OVERRIDE_GFX_VERSION', 'Not Set')
        print(f'HSA_OVERRIDE_GFX_VERSION set to: {hsa_override}')

        # Print GPU architecture information
        if hsa_override.startswith('gfx11'):
            print(f'GPU Architecture: RDNA3 (RX 7000 series)')
        elif hsa_override.startswith('gfx10'):
            if hsa_override.startswith('gfx103'):
                print(f'GPU Architecture: RDNA2 (RX 6000 series)')
            elif hsa_override.startswith('gfx101'):
                print(f'GPU Architecture: RDNA1 (RX 5000 series)')
        elif hsa_override.startswith('gfx9'):
            print(f'GPU Architecture: Vega')
        elif hsa_override.startswith('gfx8'):
            print(f'GPU Architecture: GCN 4th Gen (Polaris)')

    except Exception as e:
        print(f'[WARN] Error during GPU detail retrieval: {e}')
else:
    print('[WARN] PyTorch does not detect a compatible ROCm device.')
print(f'---------------------------')
" || echo "[WARN] PyTorch verification script encountered an error."
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
