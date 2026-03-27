#!/bin/bash
set -euo pipefail
SCRIPT_DIR_UPGRADE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR_UPGRADE/../../lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR_UPGRADE/../../lib/common.sh"
else
    echo "common.sh not found, cannot proceed." >&2; exit 1
fi

# ==============================================================================
# Upgrade Script: Migrate from ROCm 7.2.0 to ROCm 7.2.1 + ROCDXG
#
# This script safely upgrades an existing ROCm WSL AI Toolkit installation:
# 1. Backs up your old Python virtual environment
# 2. Installs ROCm 7.2.1 + builds ROCDXG (librocdxg)
# 3. Creates a fresh virtual environment with new PyTorch wheels
# 4. Reinstalls all your AI tools (ComfyUI, SD.Next, Automatic1111)
#
# YOUR MODELS AND FILES ARE NEVER TOUCHED — they live outside the venv.
# ==============================================================================

# Force PIP to ignore global user install flags which break virtual environments
export PIP_USER=0

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
VENV_BACKUP="$HOME/${VENV_NAME}_backup_$(date +%Y%m%d_%H%M%S)"
ROCM_VERSION="7.2.1"
AMDGPU_INSTALL_VERSION="7.2.1.70201-1"
LIBROCDXG_REPO="https://github.com/ROCm/librocdxg.git"
LIBROCDXG_DIR="/tmp/librocdxg"

COMFYUI_DIR="$HOME/ComfyUI"
SDNEXT_DIR="$HOME/SD.Next"
AUTOMATIC1111_DIR="$HOME/stable-diffusion-webui"

# --- Script Start ---
headline "⬆️  Upgrade to ROCm ${ROCM_VERSION} + ROCDXG"

if ! is_wsl; then
    err "This script is designed specifically for WSL2 environments."
    exit 1
fi

# ==========================================================================
# STEP 1: Pre-flight checks
# ==========================================================================
headline "STEP 1/7: Pre-flight Checks"

log "Checking existing installation..."

# Detect current ROCm version
CURRENT_ROCM="unknown"
if [ -f "/opt/rocm/.info/version" ]; then
    CURRENT_ROCM=$(cat /opt/rocm/.info/version 2>/dev/null | head -1 | tr -cd '0-9.' | head -1)
    log "Current ROCm version: ${CURRENT_ROCM}"
elif command -v rocminfo &>/dev/null; then
    CURRENT_ROCM="installed (version unknown)"
    log "ROCm appears installed but version file not found."
else
    warn "No existing ROCm installation detected."
fi

# Detect existing venv
if [ -d "$VENV_PATH" ]; then
    success "Existing venv found at: $VENV_PATH"
    # Try to get current PyTorch version
    if [ -f "$VENV_PATH/bin/activate" ]; then
        CURRENT_PYTORCH=$( source "$VENV_PATH/bin/activate" && python3 -c "import torch; print(torch.__version__)" 2>/dev/null || echo "unknown" )
        log "Current PyTorch version: ${CURRENT_PYTORCH}"
    fi
else
    warn "No existing venv found. This will be a fresh installation."
fi

# Detect installed AI tools
INSTALLED_TOOLS=()
[ -f "$COMFYUI_DIR/main.py" ] && INSTALLED_TOOLS+=("ComfyUI")
[ -f "$SDNEXT_DIR/webui.sh" ] && INSTALLED_TOOLS+=("SD.Next")
[ -f "$AUTOMATIC1111_DIR/webui.sh" ] && INSTALLED_TOOLS+=("Automatic1111")

if [ ${#INSTALLED_TOOLS[@]} -gt 0 ]; then
    success "Detected installed tools: ${INSTALLED_TOOLS[*]}"
else
    log "No AI tools detected — will perform base upgrade only."
fi

# Check ROCDXG state
if [ -f "/opt/rocm/lib/librocdxg.so" ]; then
    warn "ROCDXG (librocdxg) is already installed."
fi

# Detect Ubuntu version
UBUNTU_CODENAME=$(lsb_release -cs)
if [[ "$UBUNTU_CODENAME" == "noble" ]]; then
    PYTHON_VERSION="3.12"
    WHEEL_SUFFIX="cp312-cp312"
elif [[ "$UBUNTU_CODENAME" == "jammy" ]]; then
    PYTHON_VERSION="3.10"
    WHEEL_SUFFIX="cp310-cp310"
else
    err "Unsupported Ubuntu version: $(lsb_release -rs) (${UBUNTU_CODENAME})"
    exit 1
fi
success "Ubuntu ${UBUNTU_CODENAME} detected — Python ${PYTHON_VERSION}"

# Show summary and confirm
echo ""
if command -v gum >/dev/null 2>&1; then
    echo -e "$(gum style --bold --foreground 214 '⬆️  Upgrade Summary')\n" | gum style --border rounded --margin "0 2" --padding "1 2" --border-foreground 214
fi
echo ""
log "From: ROCm ${CURRENT_ROCM} → ROCm ${ROCM_VERSION} + ROCDXG"
log "PyTorch: ${CURRENT_PYTORCH:-unknown} → 2.9.1+rocm7.2.1"
if [ ${#INSTALLED_TOOLS[@]} -gt 0 ]; then
    log "AI Tools to re-link: ${INSTALLED_TOOLS[*]}"
fi
log "Your models, custom nodes, and extensions will NOT be touched."
echo ""

if ! yesno "Ready to Upgrade?" "This will:\n\n• Backup your old venv to ${VENV_BACKUP}\n• Upgrade ROCm to 7.2.1\n• Build & install ROCDXG (librocdxg)\n• Create a new Python venv with PyTorch 2.9.1+rocm7.2.1\n• Reinstall dependencies for: ${INSTALLED_TOOLS[*]:-none}\n\n⚠ Before proceeding, make sure you have:\n• AMD Adrenalin 26.2.2+ driver on Windows\n• Windows SDK installed on Windows\n\nYour models and files are SAFE — they are never touched."; then
    log "Upgrade cancelled by user."
    exit 0
fi

# ==========================================================================
# STEP 2: Backup existing venv
# ==========================================================================
headline "STEP 2/7: Backing Up Existing Environment"

if [ -d "$VENV_PATH" ]; then
    log "Moving old venv to: ${VENV_BACKUP}"
    mv "$VENV_PATH" "$VENV_BACKUP"
    success "Old venv backed up. You can delete it later with: rm -rf ${VENV_BACKUP}"
else
    log "No existing venv to back up."
fi

# ==========================================================================
# STEP 3: Upgrade ROCm to 7.2.1
# ==========================================================================
headline "STEP 3/7: Upgrading ROCm to ${ROCM_VERSION}"

# Check if ROCm 7.2.1 is already installed
NEEDS_ROCM_UPGRADE=true
if [ -f "/opt/rocm/.info/version" ]; then
    local_rocm=$(cat /opt/rocm/.info/version 2>/dev/null | head -1)
    if [[ "$local_rocm" == *"7.2.1"* ]]; then
        success "ROCm 7.2.1 is already installed."
        NEEDS_ROCM_UPGRADE=false
    fi
fi

if $NEEDS_ROCM_UPGRADE; then
    ensure_apt_packages wget build-essential git python3-pip python3-venv libnuma-dev pkg-config cmake gcc

    AMDGPU_INSTALL_DEB="amdgpu-install_${AMDGPU_INSTALL_VERSION}_all.deb"
    AMDGPU_INSTALL_URL="https://repo.radeon.com/amdgpu-install/7.2.1/ubuntu/${UBUNTU_CODENAME}/${AMDGPU_INSTALL_DEB}"

    log "Downloading amdgpu-install 7.2.1..."
    wget -q "$AMDGPU_INSTALL_URL" -O "/tmp/${AMDGPU_INSTALL_DEB}" || {
        err "Failed to download amdgpu-install package."
        err "URL: ${AMDGPU_INSTALL_URL}"
        exit 1
    }

    sudo apt install -y "/tmp/${AMDGPU_INSTALL_DEB}"
    rm -f "/tmp/${AMDGPU_INSTALL_DEB}"

    sudo apt update -y
    sudo apt install -y python3-setuptools python3-wheel

    log "Installing ROCm 7.2.1 packages (this may take a few minutes)..."
    sudo apt install -y rocm || {
        err "ROCm 7.2.1 installation failed."
        exit 1
    }

    # User groups
    sudo usermod -a -G render,video "$LOGNAME" 2>/dev/null || true

    success "ROCm ${ROCM_VERSION} installed."
else
    log "Skipping ROCm package installation — already at 7.2.1."
fi

# ==========================================================================
# STEP 4: Build & Install ROCDXG
# ==========================================================================
headline "STEP 4/7: Building ROCDXG (librocdxg)"

if [ -f "/opt/rocm/lib/librocdxg.so" ]; then
    warn "librocdxg.so already installed."
    if confirm "Rebuild ROCDXG anyway?"; then
        log "Proceeding with rebuild..."
    else
        success "ROCDXG build skipped."
        # Skip the build block
        SKIP_ROCDXG_BUILD=true
    fi
fi

if [ "${SKIP_ROCDXG_BUILD:-false}" != "true" ]; then
    # Auto-detect Windows SDK
    WIN_SDK_PATH=""
    WIN_KITS_BASE="/mnt/c/Program Files (x86)/Windows Kits/10/Include"
    if [ -d "$WIN_KITS_BASE" ]; then
        WIN_SDK_VERSION=$(ls -1 "$WIN_KITS_BASE" 2>/dev/null | grep -E '^10\.' | sort -V | tail -1)
        if [ -n "$WIN_SDK_VERSION" ]; then
            WIN_SDK_PATH="${WIN_KITS_BASE}/${WIN_SDK_VERSION}"
            success "Windows SDK found: ${WIN_SDK_PATH}"
        fi
    fi

    if [ -z "$WIN_SDK_PATH" ]; then
        err "Windows SDK not found!"
        err "Install it from: https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/"
        exit 1
    fi

    rm -rf "$LIBROCDXG_DIR"
    git clone --depth=1 "$LIBROCDXG_REPO" "$LIBROCDXG_DIR" || { err "Failed to clone librocdxg"; exit 1; }

    mkdir -p "$LIBROCDXG_DIR/build"
    cd "$LIBROCDXG_DIR/build"

    cmake .. -DWIN_SDK="${WIN_SDK_PATH}/shared" || { err "CMake failed"; exit 1; }
    make || { err "Build failed"; exit 1; }
    sudo make install || { err "Install failed"; exit 1; }

    cd /
    rm -rf "$LIBROCDXG_DIR"
    success "ROCDXG (librocdxg) built and installed."
fi

# ==========================================================================
# STEP 5: Create new venv + install PyTorch
# ==========================================================================
headline "STEP 5/7: Creating New Python Environment with PyTorch 2.9.1+rocm7.2.1"

python3 -m venv "$VENV_PATH"
# shellcheck disable=SC1091
source "$VENV_PATH/bin/activate"

pip install --upgrade pip wheel

# PyTorch wheels (ROCm 7.2.1)
PYTORCH_BASE_URL="https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1"
TORCH_WHEEL="torch-2.9.1+rocm7.2.1.lw.gitff65f5bc-${WHEEL_SUFFIX}-linux_x86_64.whl"
TORCHVISION_WHEEL="torchvision-0.24.0+rocm7.2.1.gitb919bd0c-${WHEEL_SUFFIX}-linux_x86_64.whl"
TORCHAUDIO_WHEEL="torchaudio-2.9.0+rocm7.2.1.gite3c6ee2b-${WHEEL_SUFFIX}-linux_x86_64.whl"
TRITON_WHEEL="triton-3.5.1+rocm7.2.1.gita272dfa8-${WHEEL_SUFFIX}-linux_x86_64.whl"

log "Downloading PyTorch wheels..."
cd /tmp

wget -q "${PYTORCH_BASE_URL}/${TORCH_WHEEL//+/%2B}" -O "${TORCH_WHEEL}" || { err "torch download failed"; exit 1; }
wget -q "${PYTORCH_BASE_URL}/${TORCHVISION_WHEEL//+/%2B}" -O "${TORCHVISION_WHEEL}" || { err "torchvision download failed"; exit 1; }
wget -q "${PYTORCH_BASE_URL}/${TORCHAUDIO_WHEEL//+/%2B}" -O "${TORCHAUDIO_WHEEL}" || { err "torchaudio download failed"; exit 1; }
wget -q "${PYTORCH_BASE_URL}/${TRITON_WHEEL//+/%2B}" -O "${TRITON_WHEEL}" || { err "triton download failed"; exit 1; }

pip3 install "${TORCH_WHEEL}" "${TORCHVISION_WHEEL}" "${TORCHAUDIO_WHEEL}" "${TRITON_WHEEL}"

log "Installing SageAttention (Triton kernel)..."
pip3 install sageattention

rm -f /tmp/*.whl

# WSL runtime fix
LOCATION=$(pip show torch | grep Location | awk -F ": " '{print $2}')
TORCH_LIB_PATH="${LOCATION}/torch/lib"
if [ -d "${TORCH_LIB_PATH}" ]; then
    rm -f "${TORCH_LIB_PATH}/libhsa-runtime64.so"*
    success "WSL runtime library fix applied."
fi

# Inject env vars into venv activation
VENV_ACTIVATE="$VENV_PATH/bin/activate"
if ! grep -q "HSA_ENABLE_DXG_DETECTION" "$VENV_ACTIVATE"; then
    echo 'export HSA_ENABLE_DXG_DETECTION=1' >> "$VENV_ACTIVATE"
fi
if ! grep -q "PIP_USER=0" "$VENV_ACTIVATE"; then
    echo 'export PIP_USER=0' >> "$VENV_ACTIVATE"
fi
if [ -n "${HSA_OVERRIDE_GFX_VERSION:-}" ]; then
    if ! grep -q "HSA_OVERRIDE_GFX_VERSION" "$VENV_ACTIVATE"; then
        echo "export HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}" >> "$VENV_ACTIVATE"
    fi
fi

success "New Python venv created with PyTorch 2.9.1+rocm7.2.1"

# ==========================================================================
# STEP 6: Reinstall AI tool dependencies
# ==========================================================================
headline "STEP 6/7: Reinstalling AI Tool Dependencies"

log "Your AI tools and models have NOT been moved — they are still in their original directories."
log "We only need to reinstall each tool's Python dependencies into the new venv."
echo ""

reinstall_count=0

# ComfyUI
if [ -f "$COMFYUI_DIR/main.py" ]; then
    log "📦 Reinstalling ComfyUI dependencies..."
    [ -f "$COMFYUI_DIR/requirements.txt" ] && pip install -r "$COMFYUI_DIR/requirements.txt" || warn "ComfyUI requirements.txt not found"

    # Reinstall custom node requirements
    if [ -d "$COMFYUI_DIR/custom_nodes" ]; then
        for node_dir in "$COMFYUI_DIR"/custom_nodes/*/; do
            if [ -f "${node_dir}requirements.txt" ]; then
                log "  → Installing deps for $(basename "$node_dir")"
                pip install -r "${node_dir}requirements.txt" 2>/dev/null || warn "  Failed for $(basename "$node_dir")"
            fi
        done
    fi
    success "ComfyUI dependencies reinstalled."
    reinstall_count=$((reinstall_count + 1))
fi

# SD.Next
if [ -f "$SDNEXT_DIR/webui.sh" ]; then
    log "📦 Reinstalling SD.Next dependencies..."
    [ -f "$SDNEXT_DIR/requirements.txt" ] && pip install -r "$SDNEXT_DIR/requirements.txt" || warn "SD.Next requirements.txt not found"
    success "SD.Next dependencies reinstalled."
    reinstall_count=$((reinstall_count + 1))
fi

# Automatic1111
if [ -f "$AUTOMATIC1111_DIR/webui.sh" ]; then
    log "📦 Reinstalling Automatic1111 dependencies..."
    [ -f "$AUTOMATIC1111_DIR/requirements.txt" ] && pip install -r "$AUTOMATIC1111_DIR/requirements.txt" || warn "Automatic1111 requirements.txt not found"

    # Reinstall extension requirements
    if [ -d "$AUTOMATIC1111_DIR/extensions" ]; then
        for ext_dir in "$AUTOMATIC1111_DIR"/extensions/*/; do
            if [ -f "${ext_dir}requirements.txt" ]; then
                log "  → Installing deps for $(basename "$ext_dir")"
                pip install -r "${ext_dir}requirements.txt" 2>/dev/null || warn "  Failed for $(basename "$ext_dir")"
            fi
        done
    fi
    success "Automatic1111 dependencies reinstalled."
    reinstall_count=$((reinstall_count + 1))
fi

if [ $reinstall_count -eq 0 ]; then
    log "No AI tools detected — base upgrade complete."
else
    success "Reinstalled dependencies for ${reinstall_count} tool(s)."
fi

# ==========================================================================
# STEP 7: Verification
# ==========================================================================
headline "STEP 7/7: Verifying Upgrade"

export HSA_ENABLE_DXG_DETECTION=1

# Check ROCDXG
if [ -f "/opt/rocm/lib/librocdxg.so" ]; then
    success "✓ ROCDXG library: /opt/rocm/lib/librocdxg.so"
else
    warn "✗ librocdxg.so not found"
fi

# Check rocminfo
if command -v rocminfo &>/dev/null; then
    rocminfo 2>/dev/null | grep -E 'Marketing Name:' | grep -i 'Radeon\|AMD' | head -1 | sed 's/^/  /' || warn "No GPU detected via rocminfo"
fi

# Check PyTorch
python3 -c "
import torch, os
print(f'  PyTorch Version: {torch.__version__}')
print(f'  ROCm Available: {torch.cuda.is_available()}')
print(f'  HSA_ENABLE_DXG_DETECTION: {os.environ.get(\"HSA_ENABLE_DXG_DETECTION\", \"Not Set\")}')
if torch.cuda.is_available():
    print(f'  GPU: {torch.cuda.get_device_name(0)}')
" || warn "PyTorch verification failed"

# ==========================================================================
# Done!
# ==========================================================================
echo ""
success "🎉 Upgrade to ROCm ${ROCM_VERSION} + ROCDXG complete!"
echo ""
warn "IMPORTANT: Restart WSL to apply group changes:"
warn "  1. Close this terminal"
warn "  2. In Windows PowerShell: wsl --shutdown"
warn "  3. Restart Ubuntu"
echo ""
log "Your old venv was backed up to:"
log "  ${VENV_BACKUP}"
log ""
log "Once verified everything works, you can delete the backup:"
log "  rm -rf ${VENV_BACKUP}"
echo ""

exit 0
