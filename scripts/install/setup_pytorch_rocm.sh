#!/bin/bash
set -euo pipefail
SCRIPT_DIR_INSTALL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source common utilities from the new 'lib' directory
if [ -f "$SCRIPT_DIR_INSTALL/../../lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR_INSTALL/../../lib/common.sh"
else
    echo "common.sh not found, cannot proceed." >&2; exit 1
fi

# ==============================================================================
# Base Environment Installer: ROCm 7.2.1 + ROCDXG + PyTorch 2.9.1
#
# AMD's official WSL instructions require building librocdxg from source
# to bridge the Windows DXCore driver to the WSL ROCm runtime.
# ==============================================================================

# Force PIP to ignore global user install flags which break virtual environments
export PIP_USER=0
# Official AMD Documentation:
# - ROCDXG WSL Guide: https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/howto_wsl.html
# - librocdxg GitHub: https://github.com/ROCm/librocdxg/
# - ROCm Quick Start: https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/quick-start.html
# - PyTorch Install: https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/native_linux/install-pytorch.html
# ==============================================================================

# --- Configuration ---
VENV_NAME="genai_env"
ROCM_VERSION="7.2.1"
AMDGPU_INSTALL_VERSION="7.2.1.70201-1"
PYTORCH_VERSION="2.9.1+rocm7.2.1"
LIBROCDXG_REPO="https://github.com/ROCm/librocdxg.git"
LIBROCDXG_DIR="/tmp/librocdxg"

# --- Script Start ---
headline "ROCm ${ROCM_VERSION} + ROCDXG + PyTorch ${PYTORCH_VERSION} Setup for WSL2"

if ! is_wsl; then
    err "This script is designed specifically for WSL2 environments."
    err "For native Linux installations, please refer to AMD's documentation."
    exit 1
fi

log "Running in Windows Subsystem for Linux (WSL2)"

# --- Detect Ubuntu Version and Python Version ---
headline "TASK 1/8: Detecting Ubuntu Version"
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_CODENAME=$(lsb_release -cs)

log "Ubuntu Version: ${UBUNTU_VERSION}"
log "Ubuntu Codename: ${UBUNTU_CODENAME}"

# Determine Python version and wheel suffix based on Ubuntu version
if [[ "$UBUNTU_CODENAME" == "noble" ]]; then
    PYTHON_VERSION="3.12"
    WHEEL_SUFFIX="cp312-cp312"
    success "Detected Ubuntu 24.04 (noble) - will use Python 3.12"
elif [[ "$UBUNTU_CODENAME" == "jammy" ]]; then
    PYTHON_VERSION="3.10"
    WHEEL_SUFFIX="cp310-cp310"
    success "Detected Ubuntu 22.04 (jammy) - will use Python 3.10"
else
    err "Unsupported Ubuntu version: ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"
    err "This installer supports Ubuntu 24.04 (noble) and 22.04 (jammy) only."
    exit 1
fi

# --- 2. System Update and Prerequisites ---
headline "TASK 2/8: System Update and Prerequisites"
ensure_apt_packages wget build-essential git python3-pip python3-venv libnuma-dev pkg-config cmake gcc
success "System update and prerequisites installation complete."

# --- 3. Install ROCm via amdgpu-install (new method for 7.2.1) ---
headline "TASK 3/8: Installing ROCm ${ROCM_VERSION}"

if command -v rocminfo &> /dev/null && [ -f "/opt/rocm/bin/rocminfo" ]; then
    warn "ROCm appears to be already installed (found /opt/rocm/bin/rocminfo)."
    if confirm "Do you want to skip ROCm installation?"; then
        success "ROCm installation skipped."
    else
        warn "Proceeding with ROCm installation. This may overwrite existing installation."
    fi
else
    log "Downloading amdgpu-install package for Ubuntu ${UBUNTU_CODENAME}..."
    
    # Download the appropriate amdgpu-install package (7.2.1)
    AMDGPU_INSTALL_DEB="amdgpu-install_${AMDGPU_INSTALL_VERSION}_all.deb"
    AMDGPU_INSTALL_URL="https://repo.radeon.com/amdgpu-install/7.2.1/ubuntu/${UBUNTU_CODENAME}/${AMDGPU_INSTALL_DEB}"
    
    wget -q "$AMDGPU_INSTALL_URL" -O "/tmp/${AMDGPU_INSTALL_DEB}" || {
        err "Failed to download amdgpu-install package from: ${AMDGPU_INSTALL_URL}"
        err "Please check your internet connection and the AMD repository status."
        exit 1
    }
    
    log "Installing amdgpu-install package..."
    sudo apt install -y "/tmp/${AMDGPU_INSTALL_DEB}"
    rm -f "/tmp/${AMDGPU_INSTALL_DEB}"
    
    log "Updating package lists..."
    sudo apt update -y
    
    log "Installing python3-setuptools and python3-wheel..."
    sudo apt install -y python3-setuptools python3-wheel
    
    log "Installing ROCm packages..."
    log "This may take several minutes. Please be patient..."
    
    # New ROCm 7.2.1 install method: use 'apt install rocm' instead of 'amdgpu-install --usecase=wsl,rocm'
    sudo apt install -y rocm || {
        err "ROCm installation failed. Please check the error messages above."
        err "For troubleshooting, see: https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/"
        exit 1
    }
    
    success "ROCm ${ROCM_VERSION} installation completed."
fi

# --- 4. User Group Configuration ---
headline "TASK 4/8: Configuring user groups"
log "Adding current user ($USER) to the 'render' and 'video' groups..."
sudo usermod -a -G render,video "$LOGNAME"

warn "Group changes require a WSL restart to take effect."
warn "In Windows PowerShell/CMD, run: wsl --shutdown"
warn "Then restart your Ubuntu terminal."

if ! confirm "Continue without restarting?"; then
    err "Installation paused. Please run 'wsl --shutdown' and restart this script."
    exit 0
fi
success "User group configuration step finished (pending WSL restart)."

# --- 5. Build & Install librocdxg (ROCDXG) ---
headline "TASK 5/8: Building & Installing ROCDXG (librocdxg)"

log "ROCDXG is the new user-mode WSL bridge library that replaces the legacy roc4wsl approach."
log "It enables ROCm GPU compute inside WSL via Microsoft's DXCore interface."

# Check if librocdxg is already installed
if [ -f "/opt/rocm/lib/librocdxg.so" ]; then
    warn "librocdxg.so already found at /opt/rocm/lib/librocdxg.so"
    if confirm "Do you want to skip ROCDXG build/install?"; then
        success "ROCDXG installation skipped."
    else
        warn "Proceeding with ROCDXG rebuild."
    fi
else
    log "Step 5a: Detecting Windows SDK path..."
    WIN_SDK_PATH=""
    
    # Auto-detect Windows SDK from common paths
    WIN_KITS_BASE="/mnt/c/Program Files (x86)/Windows Kits/10/Include"
    if [ -d "$WIN_KITS_BASE" ]; then
        # Find the latest SDK version
        WIN_SDK_VERSION=$(ls -1 "$WIN_KITS_BASE" 2>/dev/null | grep -E '^10\.' | sort -V | tail -1)
        if [ -n "$WIN_SDK_VERSION" ]; then
            WIN_SDK_PATH="${WIN_KITS_BASE}/${WIN_SDK_VERSION}"
            success "Detected Windows SDK: ${WIN_SDK_PATH}"
        fi
    fi
    
    if [ -z "$WIN_SDK_PATH" ]; then
        err "Windows SDK not found!"
        err "Please install the Windows SDK from: https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/"
        err "Common location: C:\\Program Files (x86)\\Windows Kits\\10\\Include\\10.0.26100.0\\"
        exit 1
    fi
    
    log "Step 5b: Cloning librocdxg repository..."
    rm -rf "$LIBROCDXG_DIR"
    git clone --depth=1 "$LIBROCDXG_REPO" "$LIBROCDXG_DIR" || {
        err "Failed to clone librocdxg repository."
        exit 1
    }
    
    log "Step 5c: Verifying ROCm installation for librocdxg build..."
    if [ ! -d "/opt/rocm" ]; then
        err "ROCm installation not found at /opt/rocm. Cannot build librocdxg."
        exit 1
    fi
    success "ROCm found at /opt/rocm"
    
    log "Step 5d: Building librocdxg..."
    mkdir -p "$LIBROCDXG_DIR/build"
    cd "$LIBROCDXG_DIR/build"
    
    cmake .. -DWIN_SDK="${WIN_SDK_PATH}/shared" || {
        err "CMake configuration failed for librocdxg."
        err "Check that cmake >= 3.15 and gcc >= 11.4 are installed."
        exit 1
    }
    
    make || {
        err "librocdxg build failed."
        exit 1
    }
    
    log "Step 5e: Installing librocdxg..."
    sudo make install || {
        err "librocdxg installation failed."
        exit 1
    }
    
    # Clean up build directory
    cd /
    rm -rf "$LIBROCDXG_DIR"
    
    success "ROCDXG (librocdxg) built and installed successfully."
fi

# --- 6. Setup Python Virtual Environment ---
headline "TASK 6/8: Setting up Python ${PYTHON_VERSION} virtual environment '${VENV_NAME}'"

if [ ! -d "$HOME/$VENV_NAME" ]; then
    python3 -m venv "$HOME/$VENV_NAME"
    log "Virtual environment created at $HOME/$VENV_NAME"
else
    log "Virtual environment directory $HOME/$VENV_NAME already exists."
fi

# shellcheck disable=SC1091
source "$HOME/$VENV_NAME/bin/activate"

log "Upgrading pip within the virtual environment..."
pip install --upgrade pip wheel
success "Python virtual environment setup complete. Environment activated."

# --- 7. Install PyTorch with ROCm Support ---
headline "TASK 7/8: Installing PyTorch ${PYTORCH_VERSION} via official AMD wheels"

log "Python version: $(python3 --version)"
log "Target wheel suffix: ${WHEEL_SUFFIX}"

# Define wheel URLs from AMD's official repository (ROCm 7.2.1)
PYTORCH_BASE_URL="https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1"

# Wheel filenames with proper local versions (+) - ROCm 7.2.1 git hashes
TORCH_WHEEL="torch-2.9.1+rocm7.2.1.lw.gitff65f5bc-${WHEEL_SUFFIX}-linux_x86_64.whl"
TORCHVISION_WHEEL="torchvision-0.24.0+rocm7.2.1.gitb919bd0c-${WHEEL_SUFFIX}-linux_x86_64.whl"
TORCHAUDIO_WHEEL="torchaudio-2.9.0+rocm7.2.1.gite3c6ee2b-${WHEEL_SUFFIX}-linux_x86_64.whl"
TRITON_WHEEL="triton-3.5.1+rocm7.2.1.gita272dfa8-${WHEEL_SUFFIX}-linux_x86_64.whl"

log "Downloading PyTorch wheels from repo.radeon.com..."
cd /tmp || exit 1

wget -q "${PYTORCH_BASE_URL}/${TORCH_WHEEL//+/%2B}" -O "${TORCH_WHEEL}" || {
    err "Failed to download torch wheel. Please check the URL and your connection."
    exit 1
}
wget -q "${PYTORCH_BASE_URL}/${TORCHVISION_WHEEL//+/%2B}" -O "${TORCHVISION_WHEEL}" || {
    err "Failed to download torchvision wheel."
    exit 1
}
wget -q "${PYTORCH_BASE_URL}/${TORCHAUDIO_WHEEL//+/%2B}" -O "${TORCHAUDIO_WHEEL}" || {
    err "Failed to download torchaudio wheel."
    exit 1
}
wget -q "${PYTORCH_BASE_URL}/${TRITON_WHEEL//+/%2B}" -O "${TRITON_WHEEL}" || {
    err "Failed to download pytorch_triton_rocm wheel."
    exit 1
}

success "All PyTorch wheels downloaded successfully."

log "Uninstalling any existing PyTorch packages..."
pip3 uninstall -y torch torchvision torchaudio pytorch-triton-rocm triton 2>/dev/null || true

log "Installing PyTorch wheels..."
pip3 install "${TORCH_WHEEL}" "${TORCHVISION_WHEEL}" "${TORCHAUDIO_WHEEL}" "${TRITON_WHEEL}"

log "Installing SageAttention..."
pip3 install sageattention

# Clean up downloaded wheels
rm -f /tmp/*.whl
success "PyTorch ${PYTORCH_VERSION} installation complete."

# --- WSL-specific fix for HSA runtime library ---
log "Applying WSL-specific HSA runtime library fix..."
LOCATION=$(pip show torch | grep Location | awk -F ": " '{print $2}')
TORCH_LIB_PATH="${LOCATION}/torch/lib"

if [ -d "${TORCH_LIB_PATH}" ]; then
    log "Removing bundled HSA runtime from ${TORCH_LIB_PATH}..."
    rm -f "${TORCH_LIB_PATH}/libhsa-runtime64.so"*
    success "WSL runtime library fix applied."
else
    warn "Could not find torch library path: ${TORCH_LIB_PATH}"
    warn "WSL library fix may be required manually."
fi

# Inject ROCDXG and GPU configuration into venv activation script
log "Configuring environment variables in venv activation script..."
VENV_ACTIVATE="$HOME/$VENV_NAME/bin/activate"

# Add HSA_ENABLE_DXG_DETECTION (required for ROCDXG)
if ! grep -q "HSA_ENABLE_DXG_DETECTION" "$VENV_ACTIVATE"; then
    echo 'export HSA_ENABLE_DXG_DETECTION=1' >> "$VENV_ACTIVATE"
    log "Added HSA_ENABLE_DXG_DETECTION=1 to venv activation script"
fi

if ! grep -q "PIP_USER=0" "$VENV_ACTIVATE"; then
    echo 'export PIP_USER=0' >> "$VENV_ACTIVATE"
    log "Added PIP_USER=0 to venv activation script to sandbox pip"
fi

# Add HSA_OVERRIDE_GFX_VERSION if detected
if [ -n "${HSA_OVERRIDE_GFX_VERSION:-}" ]; then
    if ! grep -q "HSA_OVERRIDE_GFX_VERSION" "$VENV_ACTIVATE"; then
        echo "export HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}" >> "$VENV_ACTIVATE"
        log "Added HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION} to venv activation script"
    fi
fi

# --- 8. Verification ---
headline "TASK 8/8: Running verification checks"

log "Verifying ROCDXG installation..."
if [ -f "/opt/rocm/lib/librocdxg.so" ]; then
    success "ROCDXG library found: /opt/rocm/lib/librocdxg.so"
else
    warn "librocdxg.so not found at /opt/rocm/lib/. ROCDXG may not be installed correctly."
fi

log "Setting HSA_ENABLE_DXG_DETECTION=1 for verification..."
export HSA_ENABLE_DXG_DETECTION=1

log "Verifying ROCm installation (rocminfo)..."
if command -v rocminfo &> /dev/null; then
    rocminfo | grep -E 'Agent [0-9]+|Name:|Marketing Name:' | grep -A2 -B1 'Agent' | grep -v -E 'Host|CPU' || warn "rocminfo did not list an AMD GPU Agent as expected."
else
    warn "rocminfo command not found. ROCm installation might be incomplete."
fi

log "Verifying PyTorch ROCm integration..."
python3 -c "
import torch, os
print(f'--- PyTorch Verification ---')
print(f'PyTorch Version: {torch.__version__}')
rocm_available = torch.cuda.is_available()
print(f'ROCm Available via torch.cuda.is_available(): {rocm_available}')
print(f'Built with ROCm (HIP): {torch.version.hip is not None}')
print(f'HSA_ENABLE_DXG_DETECTION: {os.environ.get(\"HSA_ENABLE_DXG_DETECTION\", \"Not Set\")}')
if rocm_available:
    try:
        print(f'Detected GPU Count: {torch.cuda.device_count()}')
        print(f'Detected GPU Name [0]: {torch.cuda.get_device_name(0)}')
        hsa_override = os.environ.get('HSA_OVERRIDE_GFX_VERSION', 'Not Set')
        print(f'HSA_OVERRIDE_GFX_VERSION: {hsa_override}')
    except Exception as e:
        print(f'[WARN] Error during GPU detail retrieval: {e}')
else:
    print('[WARN] PyTorch does not detect a compatible ROCm device.')
    print('[INFO] This may be normal if you have not restarted WSL after installation.')
print(f'---------------------------')
" || warn "PyTorch verification script encountered an error."

success "Verification checks complete."

# --- Script End ---
echo ""
success "ROCm ${ROCM_VERSION} + ROCDXG + PyTorch ${PYTORCH_VERSION} installation finished!"
echo ""
warn "[IMPORTANT REMINDER] You MUST restart WSL for group changes to apply:"
warn "  1. Close this terminal"
warn "  2. In Windows PowerShell/CMD, run: wsl --shutdown"
warn "  3. Restart your Ubuntu terminal"
echo ""
log "[NEXT STEPS]"
log "1. Restart WSL as instructed above"
log "2. Activate the virtual environment in new terminals:"
log "   source ~/${VENV_NAME}/bin/activate"
log "3. Use the main menu to install AI tools like ComfyUI, SD.Next, etc."
log "4. For troubleshooting, see: docs/WSL2_SETUP_GUIDE.md"
echo ""

exit 0
