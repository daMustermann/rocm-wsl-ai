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
HSA_OVERRIDE_GFX_VERSION=""
ROCM_VERSION_CHOICE="${1:-latest}" # Default to 'latest' if no argument is provided

# --- Script Start ---
headline "ROCm + PyTorch Setup for Linux & WSL2 (${ROCM_VERSION_CHOICE})"

# Exit immediately if a command exits with a non-zero status
# set -e is inherited from common.sh via pipefail

# --- GPU Detection ---
log "Detecting environment and AMD GPU..."

if is_wsl; then
    log "Running in Windows Subsystem for Linux (WSL)"
    # In WSL, get GPU info from Windows via PowerShell
    if ! command -v pwsh &> /dev/null; then
        log "Installing PowerShell to detect Windows GPU..."
        ensure_apt_packages wget apt-transport-https software-properties-common
        wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
        sudo dpkg -i /tmp/packages-microsoft-prod.deb
        rm /tmp/packages-microsoft-prod.deb
        ensure_apt_packages powershell
    fi
    GPU_INFO=$(pwsh -Command "Get-CimInstance -ClassName Win32_VideoController | Where-Object { \$_.Name -like '*Radeon*' -or \$_.Name -like '*AMD*' } | Select-Object -ExpandProperty Name")
else
    log "Running on native Linux"
    # Direct Linux detection
    if command -v lspci &> /dev/null; then
        GPU_INFO=$(lspci | grep -i 'vga\|3d\|display' | grep -i 'amd\|radeon\|ati')
    else
        warn "lspci command not found. Cannot detect GPU directly."
    fi
fi

if [ -z "$GPU_INFO" ]; then
    warn "No AMD GPU detected. This script is for AMD GPUs."
    warn "Continuing with default settings, but ROCm may not work correctly."
else
    log "Detected AMD GPU: $GPU_INFO"
fi

# --- GPU Architecture Detection and Configuration ---
if [ -n "$GPU_INFO" ]; then
    # RDNA 3.5 (Strix Point / Strix Halo APUs, e.g., Ryzen AI 300 series)
    if [[ "$GPU_INFO" =~ 1150 || "$GPU_INFO" =~ 1151 ]] || [[ "$GPU_INFO" =~ "Ryzen AI 3" ]]; then
        warn "Detected RDNA 3.5 / Ryzen AI 300 Series APU. ROCm support is EXPERIMENTAL."
        if [[ "$GPU_INFO" =~ Halo || "$GPU_INFO" =~ HX[[:space:]]3[79] ]]; then # Strix Halo (e.g. 375HX, 395HX)
             HSA_OVERRIDE_GFX_VERSION="gfx1151"; log "Setting EXPERIMENTAL HSA_OVERRIDE_GFX_VERSION=gfx1151 for Strix Halo APU";
        else # Standard Strix Point
             HSA_OVERRIDE_GFX_VERSION="gfx1150"; log "Setting EXPERIMENTAL HSA_OVERRIDE_GFX_VERSION=gfx1150 for Strix Point APU";
        fi
    # RDNA4 (Navi 4x, e.g., RX 9000 series) - Future-proofing
    elif [[ "$GPU_INFO" =~ 1200 || "$GPU_INFO" =~ 1201 ]] || [[ "$GPU_INFO" =~ RX[[:space:]]*9[0-9]{3} ]]; then
        warn "Detected RDNA4 GPU (e.g., RX 9000 series). ROCm support is EXPERIMENTAL/PRELIMINARY."
        if [[ "$GPU_INFO" =~ 99[0-9]{2} || "$GPU_INFO" =~ 1200 ]]; then HSA_OVERRIDE_GFX_VERSION="gfx1200"; log "Setting EXPERIMENTAL HSA_OVERRIDE_GFX_VERSION=gfx1200 for Navi41-based GPU";
        elif [[ "$GPU_INFO" =~ 98[0-9]{2} || "$GPU_INFO" =~ 97[0-9]{2} || "$GPU_INFO" =~ 1201 ]]; then HSA_OVERRIDE_GFX_VERSION="gfx1201"; log "Setting EXPERIMENTAL HSA_OVERRIDE_GFX_VERSION=gfx1201 for Navi42-based GPU";
        else HSA_OVERRIDE_GFX_VERSION="gfx1200"; log "Setting EXPERIMENTAL HSA_OVERRIDE_GFX_VERSION=gfx1200 for unknown RDNA4 GPU"; fi
    # RDNA3 (Navi 3x, RX 7000 series & APUs)
    elif [[ "$GPU_INFO" =~ 1100 || "$GPU_INFO" =~ 1101 || "$GPU_INFO" =~ 1102 ]] || [[ "$GPU_INFO" =~ RX[[:space:]]*7[0-9]{3} ]] || [[ "$GPU_INFO" =~ 7[0-9]{3}M ]] || [[ "$GPU_INFO" =~ "Radeon 7" ]]; then
        log "Detected RDNA3 GPU (RX 7000 series or APU)"
        if [[ "$GPU_INFO" =~ 79[0-9]{2} || "$GPU_INFO" =~ 1100 ]]; then HSA_OVERRIDE_GFX_VERSION="gfx1100"; log "Setting HSA_OVERRIDE_GFX_VERSION=gfx1100 for Navi31 GPU";
        elif [[ "$GPU_INFO" =~ 78[0-9]{2} || "$GPU_INFO" =~ 77[0-9]{2} || "$GPU_INFO" =~ 1101 ]]; then HSA_OVERRIDE_GFX_VERSION="gfx1101"; log "Setting HSA_OVERRIDE_GFX_VERSION=gfx1101 for Navi32 GPU";
        elif [[ "$GPU_INFO" =~ 76[0-9]{2} || [[ "$GPU_INFO" =~ 7[0-9]{3}M ]] || "$GPU_INFO" =~ 1102 ]]; then HSA_OVERRIDE_GFX_VERSION="gfx1102"; log "Setting HSA_OVERRIDE_GFX_VERSION=gfx1102 for Navi33/APU GPU";
        else HSA_OVERRIDE_GFX_VERSION="gfx1100"; log "Setting default HSA_OVERRIDE_GFX_VERSION=gfx1100 for RDNA3 GPU"; fi
    # RDNA2 (Navi 2x, RX 6000 series)
    elif [[ "$GPU_INFO" =~ 1030 || "$GPU_INFO" =~ 1031 || "$GPU_INFO" =~ 1032 || "$GPU_INFO" =~ 1034 ]] || [[ "$GPU_INFO" =~ RX[[:space:]]*6[0-9]{3} ]]; then
        log "Detected RDNA2 GPU (RX 6000 series)"
        if [[ "$GPU_INFO" =~ 69[0-9]{2} || "$GPU_INFO" =~ 68[0-9]{2} || "$GPU_INFO" =~ 1030 ]]; then HSA_OVERRIDE_GFX_VERSION="gfx1030"; log "Setting HSA_OVERRIDE_GFX_VERSION=gfx1030 for Navi21 GPU";
        elif [[ "$GPU_INFO" =~ 67[0-9]{2} || "$GPU_INFO" =~ 1031 ]]; then HSA_OVERRIDE_GFX_VERSION="gfx1031"; log "Setting HSA_OVERRIDE_GFX_VERSION=gfx1031 for Navi22 GPU";
        elif [[ "$GPU_INFO" =~ 66[0-9]{2} || "$GPU_INFO" =~ 1032 ]]; then HSA_OVERRIDE_GFX_VERSION="gfx1032"; log "Setting HSA_OVERRIDE_GFX_VERSION=gfx1032 for Navi23 GPU";
        elif [[ "$GPU_INFO" =~ 65[0-9]{2} || "$GPU_INFO" =~ 64[0-9]{2} || "$GPU_INFO" =~ 1034 ]]; then HSA_OVERRIDE_GFX_VERSION="gfx1034"; log "Setting HSA_OVERRIDE_GFX_VERSION=gfx1034 for Navi24 GPU";
        else HSA_OVERRIDE_GFX_VERSION="gfx1030"; log "Setting default HSA_OVERRIDE_GFX_VERSION=gfx1030 for RDNA2 GPU"; fi
    # RDNA1 (Navi 1x, RX 5000 series)
    elif [[ "$GPU_INFO" =~ 1010 || "$GPU_INFO" =~ 1012 ]] || [[ "$GPU_INFO" =~ RX[[:space:]]*5[0-9]{3} ]]; then
        log "Detected RDNA1 GPU (RX 5000 series)"
        if [[ "$GPU_INFO" =~ 57[0-9]{2} || "$GPU_INFO" =~ 56[0-9]{2} || "$GPU_INFO" =~ 1010 ]]; then HSA_OVERRIDE_GFX_VERSION="gfx1010"; log "Setting HSA_OVERRIDE_GFX_VERSION=gfx1010 for Navi10 GPU";
        elif [[ "$GPU_INFO" =~ 55[0-9]{2} || "$GPU_INFO" =~ 54[0-9]{2} || "$GPU_INFO" =~ 1012 ]]; then HSA_OVERRIDE_GFX_VERSION="gfx1012"; log "Setting HSA_OVERRIDE_GFX_VERSION=gfx1012 for Navi14 GPU";
        else HSA_OVERRIDE_GFX_VERSION="gfx1010"; log "Setting default HSA_OVERRIDE_GFX_VERSION=gfx1010 for RDNA1 GPU"; fi
    # Vega / GCN 5
    elif [[ "$GPU_INFO" =~ Vega || "$GPU_INFO" =~ Radeon[[:space:]]VII || "$GPU_INFO" =~ 90[0-9] ]]; then
        log "Detected Vega GPU"
        if [[ "$GPU_INFO" =~ Radeon[[:space:]]VII || "$GPU_INFO" =~ 906 ]]; then HSA_OVERRIDE_GFX_VERSION="gfx906"; log "Setting HSA_OVERRIDE_GFX_VERSION=gfx906 for Radeon VII";
        else HSA_OVERRIDE_GFX_VERSION="gfx900"; log "Setting HSA_OVERRIDE_GFX_VERSION=gfx900 for Vega GPU"; fi
    # Polaris / GCN 4 (RX 500/400 series)
    elif [[ "$GPU_INFO" =~ Polaris || "$GPU_INFO" =~ RX[[:space:]]*[54][0-9]{2} || "$GPU_INFO" =~ 803 ]]; then
        log "Detected Polaris GPU (RX 500/400 series)"
        HSA_OVERRIDE_GFX_VERSION="gfx803"; log "Setting HSA_OVERRIDE_GFX_VERSION=gfx803 for Polaris GPU";
    else
        warn "Could not determine specific AMD GPU architecture. Using default for RDNA3."
        HSA_OVERRIDE_GFX_VERSION="gfx1100"; log "Setting default HSA_OVERRIDE_GFX_VERSION=gfx1100";
    fi
else
    warn "No AMD GPU detected, using default configuration for RDNA3 GPUs."
    HSA_OVERRIDE_GFX_VERSION="gfx1100"; log "Setting default HSA_OVERRIDE_GFX_VERSION=gfx1100";
fi

export HSA_OVERRIDE_GFX_VERSION
log "GPU detection complete. Proceeding with installation..."

# --- 1. System Update and Prerequisites ---
headline "TASK 1/6: System Update and Prerequisites"
ensure_apt_packages wget gpg build-essential git python3-pip python3-venv libnuma-dev pkg-config
success "System update and prerequisites installation complete."

# --- 2. Install AMD GPU Drivers and ROCm ---
headline "TASK 2/6: Installing AMD graphics stack and ROCm (${ROCM_VERSION_CHOICE}) via repository"

# Determine repository path based on user choice
ROCM_REPO_PATH=""
if [ "$ROCM_VERSION_CHOICE" = "7.0-rc1" ]; then
    warn "Using experimental ROCm 7.0 RC1 repository."
    ROCM_REPO_PATH="7.0"
else # Default to "latest", which is specified as 6.4.3
    log "Using stable ROCm 6.4 series repository."
    ROCM_REPO_PATH="6.4"
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
PYTORCH_ROCM_SERIES=""
if [ "$ROCM_VERSION_CHOICE" = "7.0-rc1" ]; then
    PYTORCH_ROCM_SERIES="7.0"
else
    # For stable, we target 6.4 specifically
    PYTORCH_ROCM_SERIES="6.4"
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
