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
# Version discovery: resolves the newest ROCm release and the matching PyTorch
# wheels from AMD's repositories at run time. Nothing here is hardcoded, so a new
# ROCm release becomes installable without editing this script.
# shellcheck disable=SC1091
source "$SCRIPT_DIR_INSTALL/../../lib/version.sh"

# ==============================================================================
# Base Environment Installer
#
# Installs the newest ROCm release that AMD publishes for this Ubuntu version,
# builds librocdxg (the WSL GPU bridge), and installs the matching AMD PyTorch
# wheels. Every version is resolved from AMD's repositories at run time by
# lib/version.sh — nothing in this file is pinned, so a new ROCm release works
# without editing the script.
#
# Official AMD documentation:
# - ROCDXG WSL guide: https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/howto_wsl.html
# - librocdxg:        https://github.com/ROCm/librocdxg/
# - ROCm quick start: https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/quick-start.html
# - PyTorch wheels:   https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/native_linux/install-pytorch.html
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
LIBROCDXG_REPO="https://github.com/ROCm/librocdxg.git"
LIBROCDXG_DIR="/tmp/librocdxg"

# --- Script Start ---

if ! is_wsl; then
    err "This script is designed specifically for WSL2 environments."
    err "For native Linux installations, please refer to AMD's documentation."
    exit 1
fi

log "Running in Windows Subsystem for Linux (WSL2)"

# --- Detect Ubuntu Version and Python Version ---
headline "TASK 1/8: Detecting Ubuntu and resolving versions"
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

# --- Resolve which ROCm release to install ---
# AMD publishes several ROCm releases; we want the newest one that has both an
# apt repository for this Ubuntu release AND PyTorch wheels for this Python.
# Ask the repositories rather than trusting a version baked into this script.
log "Querying AMD's repositories for the newest release ..."

ROCM_NEWEST="$(va_latest_rocm "$UBUNTU_CODENAME")"
ROCM_VERSION="$(va_best_installable_rocm "$WHEEL_SUFFIX")"

if [ -z "$ROCM_VERSION" ]; then
    warn "Could not reach AMD's repositories. Falling back to ROCm ${ROCM_AI_FALLBACK_ROCM}."
    ROCM_VERSION="$ROCM_AI_FALLBACK_ROCM"
elif va_lt "$ROCM_VERSION" "$ROCM_NEWEST"; then
    success "ROCm ${ROCM_VERSION} selected (newest with wheels for ${WHEEL_SUFFIX}; ${ROCM_NEWEST} is published but has none yet)"
else
    success "Using the newest ROCm release: ${ROCM_VERSION}"
fi

# Resolve exact wheel filenames for this release + Python. The filenames embed a
# git hash that changes with every ROCm patch, which is why nothing is pinned.
WHEELS=""
if ! WHEELS="$(va_resolve_torch_wheels "$ROCM_VERSION" "$WHEEL_SUFFIX")"; then
    err "Could not resolve PyTorch wheels for ROCm ${ROCM_VERSION} / ${WHEEL_SUFFIX}."
    err "Check:  https://repo.radeon.com/rocm/manylinux/rocm-rel-${ROCM_VERSION}/"
    err ""
    err "If you are offline, install with a known-good version by editing this"
    err "script's ROCM_VERSION after the resolve step, or run:  ./upgrade.sh --check"
    exit 1
fi

ROCM_REL="" TORCH_VERSION="" TORCH_WHEEL="" TORCHVISION_WHEEL="" TORCHAUDIO_WHEEL="" TRITON_WHEEL=""
eval "$WHEELS"

PYTORCH_VERSION="${TORCH_VERSION}+rocm${ROCM_REL}"
LIBROCDXG_TAG="$(va_latest_librocdxg)"

headline "Installing ROCm ${ROCM_VERSION} + ROCDXG ${LIBROCDXG_TAG} + PyTorch ${PYTORCH_VERSION}"
printf '\n'
log "This will install:"
log "  ROCm       ${ROCM_VERSION}"
log "  ROCDXG     ${LIBROCDXG_TAG} (built from source)"
log "  PyTorch    ${TORCH_VERSION}"
printf '\n'

if [ "${ROCM_AI_ASSUME_YES:-0}" != "1" ] && ! confirm "Proceed with the installation?"; then
    log "Cancelled."
    exit 0
fi

# --- 2. System Update and Prerequisites ---
headline "TASK 2/8: System Update and Prerequisites"
ensure_apt_packages wget build-essential git python3-pip python3-venv libnuma-dev pkg-config cmake gcc
success "System update and prerequisites installation complete."

# --- 3. Install ROCm from AMD's signed apt repository ---
headline "TASK 3/8: Installing ROCm ${ROCM_VERSION}"

if command -v rocminfo &> /dev/null && [ -f "/opt/rocm/bin/rocminfo" ]; then
    ROCM_PRESENT="$(va_rocm_installed 2>/dev/null || echo unknown)"
    if [ "$ROCM_PRESENT" = "$ROCM_VERSION" ]; then
        success "ROCm ${ROCM_VERSION} is already installed."
    else
        warn "ROCm ${ROCM_PRESENT} is installed; this installer targets ${ROCM_VERSION}."
        if confirm "Upgrade ROCm to ${ROCM_VERSION}?"; then
            INSTALL_ROCM=1
        else
            success "Keeping the installed ROCm."
        fi
    fi
else
    INSTALL_ROCM=1
fi

if [ "${INSTALL_ROCM:-0}" = "1" ]; then
    # --- apt source, not amdgpu-install --------------------------------------
    # The amdgpu-install .deb path required guessing a build number that changes
    # independently of the ROCm version (e.g. 7.2.3.70203-1) and broke whenever
    # AMD republished. Adding the signed repository directly and installing the
    # `rocm` metapackage is what AMD's own quick-start recommends, and it lets
    # apt resolve dependencies and produce sensible upgrade paths.
    KEYRING="/etc/apt/keyrings/rocm.gpg"

    if [ ! -f "$KEYRING" ]; then
        log "Installing AMD's repository signing key..."
        sudo mkdir -p /etc/apt/keyrings
        wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key \
            | gpg --dearmor | sudo tee "$KEYRING" >/dev/null || {
                err "Failed to install the ROCm signing key."
                err "Please check your internet connection."
                exit 1
            }
    fi

    # Amend an existing source rather than adding a second, conflicting one.
    EXISTING_SRC="$(grep -rl 'repo.radeon.com/rocm/apt' /etc/apt/sources.list.d/ 2>/dev/null | head -1)"
    if [ -n "$EXISTING_SRC" ]; then
        log "Updating the ROCm apt source to ${ROCM_VERSION} ..."
        sudo sed -i -E "s|https://repo\.radeon\.com/rocm/apt/[0-9.]+|https://repo.radeon.com/rocm/apt/${ROCM_VERSION}|g" "$EXISTING_SRC" \
            || warn "Could not rewrite $EXISTING_SRC"
    else
        log "Adding the ROCm ${ROCM_VERSION} apt source..."
        printf 'deb [arch=amd64 signed-by=%s] https://repo.radeon.com/rocm/apt/%s %s main\n' \
            "$KEYRING" "$ROCM_VERSION" "$UBUNTU_CODENAME" \
            | sudo tee /etc/apt/sources.list.d/rocm.list >/dev/null || {
                err "Could not write the ROCm apt source."
                exit 1
            }
    fi

    # The graphics repository carries userspace pieces ROCm depends on.
    if _va_curl -o /dev/null "https://repo.radeon.com/graphics/${ROCM_VERSION}/ubuntu/dists/${UBUNTU_CODENAME}/Release"; then
        GRAPHICS_SRC="$(grep -rl 'repo.radeon.com/graphics' /etc/apt/sources.list.d/ 2>/dev/null | head -1)"
        if [ -n "$GRAPHICS_SRC" ]; then
            sudo sed -i -E "s|repo\.radeon\.com/graphics/[0-9.]+|repo.radeon.com/graphics/${ROCM_VERSION}|g" "$GRAPHICS_SRC" || true
        else
            printf 'deb [arch=amd64 signed-by=%s] https://repo.radeon.com/graphics/%s/ubuntu %s main\n' \
                "$KEYRING" "$ROCM_VERSION" "$UBUNTU_CODENAME" \
                | sudo tee /etc/apt/sources.list.d/rocm-graphics.list >/dev/null || true
        fi
    fi

    log "Refreshing package lists..."
    sudo apt-get update -y >/dev/null 2>&1 || {
        err "apt-get update failed. The ROCm ${ROCM_VERSION} repository may be unreachable."
        exit 1
    }

    log "Installing ROCm packages (several GB; this takes a while)..."
    sudo apt-get install -y python3-setuptools python3-wheel >/dev/null 2>&1 || true
    sudo apt-get install -y rocm || {
        err "ROCm installation failed. Please check the error messages above."
        err "For troubleshooting, see: https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/"
        exit 1
    }

    success "ROCm $(va_rocm_installed 2>/dev/null || echo "$ROCM_VERSION") installation completed."
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
    ROCDXG_PRESENT="$(va_rocdxg_installed 2>/dev/null || echo unknown)"
    if confirm "ROCDXG ${ROCDXG_PRESENT} is installed. Rebuild it as ${LIBROCDXG_TAG}?"; then
        warn "Proceeding with the ROCDXG rebuild."
    else
        success "ROCDXG installation skipped."
        SKIP_ROCDXG=1
    fi
fi

if [ "${SKIP_ROCDXG:-0}" != "1" ]; then
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
    
    log "Step 5b: Cloning librocdxg (${LIBROCDXG_TAG}) ..."
    rm -rf "$LIBROCDXG_DIR"
    # Prefer the resolved release tag; fall back to the default branch.
    if ! git clone --depth=1 --branch "$LIBROCDXG_TAG" "$LIBROCDXG_REPO" "$LIBROCDXG_DIR" 2>/dev/null; then
        warn "Tag ${LIBROCDXG_TAG} unavailable; using the default branch."
        git clone --depth=1 "$LIBROCDXG_REPO" "$LIBROCDXG_DIR" || {
            err "Failed to clone librocdxg repository."
            exit 1
        }
    fi
    
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

# Wheel names, versions and the ROCm release directory were all resolved from
# AMD's repository index at the top of this script (see va_resolve_torch_wheels).
PYTORCH_BASE_URL="https://repo.radeon.com/rocm/manylinux/rocm-rel-${ROCM_REL}"

log "Downloading PyTorch wheels from repo.radeon.com ..."
WHEEL_TMP="$(mktemp -d /tmp/rocm-wheels.XXXXXX)"
cd "$WHEEL_TMP" || exit 1

for w in "$TORCH_WHEEL" "$TORCHVISION_WHEEL" "$TORCHAUDIO_WHEEL" "$TRITON_WHEEL"; do
    log "  $(printf '%s' "$w" | cut -c1-64)"
    wget -q "${PYTORCH_BASE_URL}/${w//+/%2B}" -O "$w" || {
        err "Failed to download: $w"
        err "URL: ${PYTORCH_BASE_URL}/${w//+/%2B}"
        err "Please check your internet connection."
        exit 1
    }
done

success "All PyTorch wheels downloaded successfully."

log "Uninstalling any existing PyTorch packages..."
pip3 uninstall -y torch torchvision torchaudio pytorch-triton-rocm triton 2>/dev/null || true

log "Installing PyTorch wheels..."
pip3 install "$TORCH_WHEEL" "$TORCHVISION_WHEEL" "$TORCHAUDIO_WHEEL" "$TRITON_WHEEL"

log "Installing SageAttention..."
pip3 install sageattention || warn "SageAttention not installed (optional)"

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

# Inject the GPU environment into venv activation script.
#
# Deliberately minimal. The real GPU environment is applied by lib/launch.sh
# before Python starts, and these two lines are a convenience for people who
# activate the venv by hand.
#
# Notably absent: HSA_OVERRIDE_GFX_VERSION. Version 3.x wrote it here if it
# happened to be set, and with ROCDXG installed an override makes the runtime
# reject the device — the GPU then disappears from PyTorch while rocminfo still
# reports it. It must never be persisted into an activation script.
log "Configuring environment variables in venv activation script..."
VENV_ACTIVATE="$HOME/$VENV_NAME/bin/activate"

if ! grep -q "HSA_ENABLE_DXG_DETECTION" "$VENV_ACTIVATE"; then
    echo 'export HSA_ENABLE_DXG_DETECTION=1' >> "$VENV_ACTIVATE"
    log "Added HSA_ENABLE_DXG_DETECTION=1 to venv activation script"
fi

if ! grep -q "PIP_USER=0" "$VENV_ACTIVATE"; then
    echo 'export PIP_USER=0' >> "$VENV_ACTIVATE"
    log "Added PIP_USER=0 to venv activation script to sandbox pip"
fi

# Make the GPU usable from any terminal, not just an activated venv. This is the
# fix for the most common "PyTorch cannot see my GPU" report.
log "Installing the GPU environment for login shells..."
if rocm_ai_install_shell_integration; then
    success "GPU environment installed for new login shells."
else
    warn "Could not install the login-shell environment automatically."
    warn "See docs/TROUBLESHOOTING.md -> 'PyTorch can't see my GPU'."
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
