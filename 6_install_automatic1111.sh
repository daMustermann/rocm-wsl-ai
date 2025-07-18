#!/bin/bash

# ==============================================================================
# Script to install Automatic1111 Stable Diffusion WebUI with ROCm support
# Compatible with Ubuntu 24.04 LTS and WSL2
# ==============================================================================

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
WEBUI_DIR="$HOME/stable-diffusion-webui"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# --- Functions ---
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_info() {
    echo -e "${PURPLE}[INFO] $1${NC}"
}

# --- Script Start ---
print_header "Installing Automatic1111 Stable Diffusion WebUI"

# Exit immediately if a command exits with a non-zero status
set -e

# --- 1. Check Prerequisites ---
print_info "Checking prerequisites..."

if [ ! -f "$VENV_PATH/bin/activate" ]; then
    print_error "Python virtual environment not found at $VENV_PATH"
    print_error "Please run the ROCm/PyTorch setup script first (1_setup_pytorch_rocm_wsl.sh)"
    exit 1
fi

print_success "Prerequisites check passed"

# --- 2. Activate Virtual Environment ---
print_info "Activating Python virtual environment..."
source "$VENV_PATH/bin/activate"
print_success "Virtual environment activated"

# --- 3. Clone Automatic1111 Repository ---
print_info "Cloning Automatic1111 Stable Diffusion WebUI..."

if [ ! -d "$WEBUI_DIR" ]; then
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$WEBUI_DIR"
    print_success "Repository cloned successfully"
else
    print_warning "Directory already exists at $WEBUI_DIR"
    print_info "Updating existing installation..."
    cd "$WEBUI_DIR"
    git pull
    cd "$HOME"
fi

# --- 4. Install Dependencies ---
print_info "Installing additional dependencies for ROCm..."

# Install required system packages
sudo apt update
sudo apt install -y wget git python3-pip python3-venv libgl1 libglib2.0-0

# --- 5. Configure for ROCm ---
print_info "Configuring WebUI for ROCm support..."

cd "$WEBUI_DIR"

# Create or update webui-user.sh for ROCm
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

chmod +x webui-user.sh

# --- 6. Install Essential Extensions ---
print_info "Installing useful extensions..."

cd extensions

# ControlNet extension (very popular)
if [ ! -d "sd-webui-controlnet" ]; then
    git clone https://github.com/Mikubill/sd-webui-controlnet.git sd-webui-controlnet
    print_success "ControlNet extension installed"
fi

# OpenPose Editor
if [ ! -d "openpose-editor" ]; then
    git clone https://github.com/fkunn1326/openpose-editor.git openpose-editor
    print_success "OpenPose Editor extension installed"
fi

# Image Browser
if [ ! -d "stable-diffusion-webui-images-browser" ]; then
    git clone https://github.com/AlUlkesh/stable-diffusion-webui-images-browser.git stable-diffusion-webui-images-browser
    print_success "Image Browser extension installed"
fi

# Additional Networks (for LoRA support)
if [ ! -d "sd-webui-additional-networks" ]; then
    git clone https://github.com/kohya-ss/sd-webui-additional-networks.git sd-webui-additional-networks
    print_success "Additional Networks extension installed"
fi

cd "$WEBUI_DIR"

# --- 7. Create Launch Script ---
print_info "Creating launch script..."

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

chmod +x launch_webui_rocm.sh

# --- 8. Create Desktop Shortcut (if in GUI environment) ---
if [ ! -z "$DISPLAY" ] || [ ! -z "$WAYLAND_DISPLAY" ]; then
    print_info "Creating desktop shortcut..."
    
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
    print_success "Desktop shortcut created"
fi

cd "$HOME"

# --- 9. Final Configuration ---
print_info "Performing final setup..."

# Ensure correct permissions
chmod +x "$WEBUI_DIR/webui.sh"
chmod +x "$WEBUI_DIR/launch_webui_rocm.sh"

print_header "Installation Complete!"

echo -e "${GREEN}Automatic1111 Stable Diffusion WebUI has been installed successfully!${NC}"
echo ""
echo -e "${YELLOW}To start the WebUI:${NC}"
echo -e "1. Run: ${BLUE}cd $WEBUI_DIR && ./launch_webui_rocm.sh${NC}"
echo -e "2. Or run: ${BLUE}$WEBUI_DIR/launch_webui_rocm.sh${NC}"
echo -e "3. Open your browser and go to: ${BLUE}http://127.0.0.1:7860${NC}"
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo -e "• First startup will take longer as it downloads the base model"
echo -e "• Download additional models to: ${BLUE}$WEBUI_DIR/models/Stable-diffusion/${NC}"
echo -e "• ControlNet models go to: ${BLUE}$WEBUI_DIR/extensions/sd-webui-controlnet/models/${NC}"
echo -e "• If you experience memory issues, try reducing image resolution"
echo -e "• The WebUI includes ControlNet, OpenPose Editor, and other useful extensions"
echo ""
echo -e "${YELLOW}For troubleshooting:${NC}"
echo -e "• Check that ROCm is working: ${BLUE}rocminfo${NC}"
echo -e "• Verify PyTorch ROCm support: ${BLUE}python3 -c 'import torch; print(torch.cuda.is_available())'${NC}"
echo -e "• Adjust HSA_OVERRIDE_GFX_VERSION in webui-user.sh for your specific GPU"
echo ""
print_success "Installation completed successfully!"
