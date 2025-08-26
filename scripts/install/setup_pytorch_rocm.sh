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
# Script to install AMD GPU drivers (ROCm), PyTorch, and Triton
# for generative AI on Ubuntu (Native & WSL2).
#
# Auto-detects AMD GPU and applies appropriate configurations.
# Always uses the 'latest' ROCm repo and matching PyTorch Nightly.
# ==============================================================================

# --- Configuration ---
VENV_NAME="genai_env"
ROCM_VERSION_CHOICE="${1:-latest}" # Default to 'latest' if no argument is provided

# --- Script Start ---
headline "ROCm + PyTorch Setup for Linux & WSL2 (${ROCM_VERSION_CHOICE})"

# Exit immediately if a command exits with a non-zero status
# set -e is inherited from common.sh via pipefail

# GPU detection is now handled by 'lib/common.sh' sourcing 'scripts/utils/gpu_config.sh'.
# This ensures detection is centralized and runs before this script.
# The necessary environment variables (HSA_OVERRIDE_GFX_VERSION, PYTORCH_ROCM_ARCH)
# are automatically exported and available to this script.
log "GPU auto-detection is handled by lib/common.sh"
if is_wsl; then log "Running in Windows Subsystem for Linux (WSL)"; else log "Running on native Linux"; fi
log "Using detected HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION:-Not Set}"

# --- 1. System Update and Prerequisites ---
headline "TASK 1/6: System Update and Prerequisites"
ensure_apt_packages wget gpg build-essential git python3-pip python3-venv libnuma-dev pkg-config
success "System update and prerequisites installation complete."

# --- 2. Install AMD GPU Drivers and ROCm ---
headline "TASK 2/6: Installing AMD graphics stack and ROCm (${ROCM_VERSION_CHOICE}) via repository"

if [ -f "/opt/rocm/bin/rocminfo" ]; then
    warn "ROCm appears to be already installed (found /opt/rocm/bin/rocminfo)."
    warn "Skipping ROCm system package installation to protect your existing setup."
    warn "If you want to force a re-installation, please remove ROCm first."
    success "ROCm system package installation skipped."
else
    # Determine repository path based on user choice
    ROCM_REPO_PATH=""
    if [ "$ROCM_VERSION_CHOICE" = "7.0-rc1" ]; then
        warn "Using experimental ROCm 7.0 RC1 repository."
        ROCM_REPO_PATH="7.0"
    else # Default to "latest"
        log "Using latest stable ROCm repository."
        ROCM_REPO_PATH="latest"
    fi

    # Add ROCm repository
    if [ ! -f /etc/apt/sources.list.d/rocm.list ]; then
        log "Adding ROCm '${ROCM_REPO_PATH}' apt repository..."
        wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | sudo apt-key add -
        echo "deb [arch=amd64] https://repo.radeon.com/rocm/apt/${ROCM_REPO_PATH} jammy main" | sudo tee /etc/apt/sources.list.d/rocm.list
    else
        log "ROCm repository file already exists. Ensure it matches your selection."
        # Optional: could add logic here to switch the repo if it's different
    fi
    sudo apt update

    if is_wsl; then
        log "Installing WSL-specific packages (no DKMS)..."
        ensure_apt_packages mesa-utils mesa-vulkan-drivers vulkan-tools mesa-opencl-icd clinfo firmware-amd-graphics
        ensure_apt_packages rocm-dev rocm-libs rocm-utils rocminfo rocm-smi hip-dev hipcc miopen-hip rocblas rocsolver rocfft rocsparse rccl
    else
        log "Installing native Linux packages (with DKMS)..."
        ensure_apt_packages amdgpu-dkms
        ensure_apt_packages rocm
    fi
    success "AMD graphics & ROCm installation via apt completed."
fi

# --- 3. User Group Configuration ---
headline "TASK 3/6: Configuring user groups"
log "Adding current user ($USER) to the 'render' and 'video' groups..."
sudo usermod -a -G render,video "$LOGNAME"

warn "Group changes require a restart/re-login to take effect."
if is_wsl; then
    warn "In WSL, run 'wsl --shutdown' in Windows PowerShell/CMD, then restart your Ubuntu terminal."
fi
if ! confirm "Continue without restarting?"; then
    err "Exiting. Please restart and run the script again."
    exit 1
fi
success "User group configuration step finished (pending restart)."

# --- 4. Setup Python Virtual Environment ---
headline "TASK 4/6: Setting up Python virtual environment '${VENV_NAME}'"
if [ ! -d "$HOME/$VENV_NAME" ]; then
    python3 -m venv "$HOME/$VENV_NAME"
    log "Virtual environment created at $HOME/$VENV_NAME"
else
    log "Virtual environment directory $HOME/$VENV_NAME already exists."
fi

source "$HOME/$VENV_NAME/bin/activate"
log "Upgrading pip within the virtual environment..."
pip install --upgrade pip wheel
success "Python virtual environment setup complete. Environment activated."

# --- 5. Install PyTorch with ROCm Support & Triton ---
headline "TASK 5/6: Installing PyTorch Nightly for matching ROCm series + Triton"

# Determine PyTorch index based on ROCm choice
# NOTE: These might need updating as new ROCm versions are released and supported by PyTorch.
# As of mid-2024, 6.1 is the latest stable series with nightly wheels. 7.0 is experimental.
PYTORCH_ROCM_STABLE_SERIES="6.1"
PYTORCH_ROCM_EXPERIMENTAL_SERIES="7.0"

PYTORCH_ROCM_SERIES=""
if [ "$ROCM_VERSION_CHOICE" = "7.0-rc1" ]; then
    PYTORCH_ROCM_SERIES="$PYTORCH_ROCM_EXPERIMENTAL_SERIES"
    log "Selected experimental ROCm, targeting PyTorch for ROCm ${PYTORCH_ROCM_SERIES}"
else
    # For "latest", we target the latest known stable PyTorch series
    PYTORCH_ROCM_SERIES="$PYTORCH_ROCM_STABLE_SERIES"
    log "Selected latest stable ROCm, targeting PyTorch for ROCm ${PYTORCH_ROCM_SERIES}"
fi
log "Targeting ROCm series: ${PYTORCH_ROCM_SERIES}"

PYTORCH_INDEX_URL="https://download.pytorch.org/whl/nightly/rocm${PYTORCH_ROCM_SERIES}"
log "Using PyTorch Nightly index: ${PYTORCH_INDEX_URL}"

pip install --pre torch torchvision torchaudio --index-url "${PYTORCH_INDEX_URL}"

if [ -n "$HSA_OVERRIDE_GFX_VERSION" ]; then
    echo "export HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}" >> "$HOME/$VENV_NAME/bin/activate"
    log "Added HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION} to venv activation script"
fi

if is_wsl; then
    log "Performing WSL-specific PyTorch library path update..."
    LOCATION=$(pip show torch | grep Location | awk -F ": " '{print $2}')
    TORCH_LIB_PATH="${LOCATION}/torch/lib"
    if [ -d "${TORCH_LIB_PATH}" ]; then
        SYSTEM_HSA_LIB="/opt/rocm/lib/libhsa-runtime64.so.1"
        if [ -f "${SYSTEM_HSA_LIB}" ]; then
            log "Removing potentially bundled HSA runtime from ${TORCH_LIB_PATH}..."
            rm -f "${TORCH_LIB_PATH}/libhsa-runtime64.so"*
            log "Creating symlink from system ROCm library to PyTorch directory..."
            ln -s "${SYSTEM_HSA_LIB}" "${TORCH_LIB_PATH}/"
            success "Symlink created."
        else
            warn "System HSA runtime library not found at ${SYSTEM_HSA_LIB}. Skipping WSL symlink."
        fi
    else
        warn "Could not find torch library path: ${TORCH_LIB_PATH}. Skipping WSL library path update."
    fi
fi

log "Installing Triton (pre-release may be required)..."
pip install -U --pre triton || warn "Triton nightly not available; continuing"
success "PyTorch and Triton installation complete."

# --- 6. Verification ---
headline "TASK 6/6: Running verification checks"

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
if rocm_available:
    try:
        print(f'Detected GPU Count: {torch.cuda.device_count()}')
        print(f'Detected GPU Name [0]: {torch.cuda.get_device_name(0)}')
        hsa_override = os.environ.get('HSA_OVERRIDE_GFX_VERSION', 'Not Set')
        print(f'HSA_OVERRIDE_GFX_VERSION set to: {hsa_override}')
        arch = 'Unknown'
        if hsa_override.startswith('gfx12'): arch = 'RDNA4 (RX 9000 series) - EXPERIMENTAL'
        elif hsa_override.startswith('gfx115'): arch = 'RDNA3.5 (Ryzen AI 300 Series) - EXPERIMENTAL'
        elif hsa_override.startswith('gfx11'): arch = 'RDNA3 (RX 7000 series)'
        elif hsa_override.startswith('gfx103'): arch = 'RDNA2 (RX 6000 series)'
        elif hsa_override.startswith('gfx101'): arch = 'RDNA1 (RX 5000 series)'
        elif hsa_override.startswith('gfx9'): arch = 'Vega'
        elif hsa_override.startswith('gfx8'): arch = 'GCN 4th Gen (Polaris)'
        print(f'GPU Architecture: {arch}')
    except Exception as e:
        print(f'[WARN] Error during GPU detail retrieval: {e}')
else:
    print('[WARN] PyTorch does not detect a compatible ROCm device.')
print(f'---------------------------')
" || warn "PyTorch verification script encountered an error."

log "Verifying Triton installation (basic import)..."
python3 -c 'import triton; print(f"Triton Version: {triton.__version__}")' || warn "Failed to import Triton."
success "Verification checks complete."

# --- Script End ---
echo ""
success "ROCm + PyTorch Nightly + Triton installation finished!"
echo ""
warn "[IMPORTANT REMINDER] If you haven't already, RESTART your system or WSL session for group changes to apply."
echo ""
log "[NEXT STEPS]"
log "1. Ensure your system/WSL has been restarted."
log "2. Activate the virtual environment in new terminals BEFORE running AI apps:"
log "   source ~/${VENV_NAME}/bin/activate"
log "3. You can now use the main menu to install AI tools like ComfyUI, SD.Next, etc."
echo ""

exit 0
