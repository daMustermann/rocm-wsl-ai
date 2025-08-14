#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$0")"
COMMON="$SCRIPT_DIR/common.sh"
[ -f "$COMMON" ] && source "$COMMON" || { echo "common.sh not found"; exit 1; }

VENV_NAME="genai_env"
WEBUI_DIR="$HOME/stable-diffusion-webui"

standard_header "Automatic1111 Stable Diffusion WebUI"
ensure_venv "$VENV_NAME" || { err "Run 1_setup_pytorch_rocm_wsl.sh first"; exit 1; }

ensure_apt_packages wget git python3-pip python3-venv libgl1 libglib2.0-0
git_clone_or_update https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$WEBUI_DIR"

cd "$WEBUI_DIR"
cat > webui-user.sh << 'EOF'
#!/bin/bash

# ROCm Configuration for Automatic1111 WebUI
export COMMANDLINE_ARGS="--precision full --no-half --opt-split-attention --use-cpu interrogate"

# ROCm specific environment variables
export HSA_OVERRIDE_GFX_VERSION="12.0.0"  # Adjust based on your GPU (e.g., 12.0.0 for RDNA4, 11.0.0 for RDNA3)
export PYTORCH_ROCM_ARCH="gfx1200;gfx1201;gfx1100;gfx1101;gfx1102"  # RDNA4 & RDNA3 support
export GPU_FORCE_64BIT_PTR=1
export GPU_MAX_HEAP_SIZE="100%"
export GPU_MAX_ALLOC_PERCENT="100%"
export GPU_USE_SYNC_OBJECTS=1

# Use system PyTorch instead of downloading CUDA version
export TORCH_COMMAND="pip install torch==2.8.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.4"

# Disable some CUDA-specific optimizations
export PYTORCH_CUDA_ALLOC_CONF=""

# Memory optimization
export PYTORCH_ROCM_ALLOW_UNALIGNED_ACCESS=1
EOF

chmod +x webui-user.sh || warn "chmod webui-user.sh failed"

declare -a EXT_LIST=( \
    "sd-webui-controlnet|https://github.com/Mikubill/sd-webui-controlnet.git" \
    "openpose-editor|https://github.com/fkunn1326/openpose-editor.git" \
    "stable-diffusion-webui-images-browser|https://github.com/AlUlkesh/stable-diffusion-webui-images-browser.git" \
    "sd-webui-additional-networks|https://github.com/kohya-ss/sd-webui-additional-networks.git" )

mkdir -p extensions
for entry in "${EXT_LIST[@]}"; do
    name="${entry%%|*}"; repo="${entry##*|}";
    if [ ! -d "extensions/$name" ]; then
        log "Adding extension $name"
        git clone --depth=1 "$repo" "extensions/$name" || warn "Failed to clone $name"
    else
        git -C "extensions/$name" pull --rebase --autostash >/dev/null 2>&1 || true
    fi
done

cat > launch_webui_rocm.sh << 'EOF'
#!/bin/bash

# Activate the genai_env virtual environment
source ~/genai_env/bin/activate

# Set ROCm environment variables
export HSA_OVERRIDE_GFX_VERSION="12.0.0"  # Adjust for your GPU
export PYTORCH_ROCM_ARCH="gfx1200;gfx1201;gfx1100;gfx1101;gfx1102"
export GPU_FORCE_64BIT_PTR=1
export GPU_MAX_HEAP_SIZE="100%"
export GPU_MAX_ALLOC_PERCENT="100%"

# Navigate to WebUI directory
cd ~/stable-diffusion-webui

# Launch WebUI
echo "Starting Automatic1111 WebUI with ROCm support..."
echo "Once started, open http://127.0.0.1:7860 in your browser"
echo "Use Ctrl+C to stop the server"

./webui.sh --listen --enable-insecure-extension-access
EOF

chmod +x launch_webui_rocm.sh || warn "chmod launch_webui_rocm.sh failed"

if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    cat > "$HOME/Desktop/Automatic1111_WebUI.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Automatic1111 WebUI (ROCm)
Comment=Stable Diffusion WebUI with AMD GPU support
Exec=$WEBUI_DIR/launch_webui_rocm.sh
Icon=applications-graphics
Terminal=true
Categories=Graphics;Photography;
EOF
    chmod +x "$HOME/Desktop/Automatic1111_WebUI.desktop"
fi
cd "$HOME"
success "Automatic1111 install/update complete"
cat <<EOF
Launch: $WEBUI_DIR/launch_webui_rocm.sh
Open:   http://127.0.0.1:7860
Models: $WEBUI_DIR/models/Stable-diffusion/
ControlNet models: $WEBUI_DIR/extensions/sd-webui-controlnet/models/
Check ROCm: rocminfo | grep Agent
Torch ROCm avail: python -c 'import torch; print(torch.cuda.is_available())'
EOF

exit 0
