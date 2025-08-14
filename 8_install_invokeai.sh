#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh" || { echo "common.sh missing" >&2; exit 1; }

VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
INVOKEAI_DIR="$HOME/InvokeAI"

standard_header "Installing InvokeAI (Image Generation Suite)"

# --- 1. Check Prerequisites ---
log "Checking prerequisites..."

if [ ! -f "$VENV_PATH/bin/activate" ]; then
    err "Virtual environment missing: $VENV_PATH"
    err "Run 1_setup_pytorch_rocm_wsl.sh first."; exit 1
fi
success "Prerequisites check passed"

# --- 2. Activate Virtual Environment ---
log "Activating virtual environment..."
source "$VENV_PATH/bin/activate"

# Verify PyTorch ROCm support
python3 - <<'PY'
import torch, sys
if not torch.cuda.is_available():
    print('ROCm acceleration not available in this PyTorch build', file=sys.stderr)
    sys.exit(1)
print('PyTorch ROCm OK (torch', torch.__version__, ')')
PY
success "Virtual environment active and ROCm available"

# --- 3. Create InvokeAI Directory ---
log "Preparing directory..."

mkdir -p "$INVOKEAI_DIR"
cd "$INVOKEAI_DIR"

# Set InvokeAI root directory
export INVOKEAI_ROOT="$INVOKEAI_DIR"

success "Directory ready: $INVOKEAI_DIR"

# --- 4. Install InvokeAI ---
log "Installing InvokeAI (PyPI) ..."

# Install InvokeAI with PyTorch index for ROCm
pip install InvokeAI --use-pep517 --extra-index-url https://download.pytorch.org/whl/rocm6.4

success "InvokeAI package installed"

# --- 5. Configure InvokeAI ---
log "Writing configuration files..."

# Create configuration file
mkdir -p "$INVOKEAI_DIR/configs"

cat > "$INVOKEAI_DIR/invokeai.yaml" << 'EOF'
# InvokeAI Configuration for ROCm
InvokeAI:
  Features:
    always_use_cpu: false
    internet_available: true
    log_tokenization: false
    patchmatch: true
    ignore_missing_core_models: false
  
  Generation:
    sequential_guidance: false
    attention_type: sliced
    attention_slice_size: auto
    forced_tiled_decode: false
    png_compress_level: 6
    max_cache_size: 6.0
    max_vram_cache_size: 2.75
    
  Device:
    device: auto
    precision: auto
    
  Model_Store:
    scan_models_on_startup: true
    convert_cache_size: 20
    
  Logging:
    version: 4.0.0
EOF

# Create environment setup script
cat > "$INVOKEAI_DIR/setup_env.sh" << 'EOF'
#!/bin/bash

# InvokeAI ROCm environment (auto-detected GPU settings)
export INVOKEAI_HOME=~/invokeai
[ -f "$HOME/.config/rocm-wsl-ai/gpu.env" ] && source "$HOME/.config/rocm-wsl-ai/gpu.env"
: "${HSA_OVERRIDE_GFX_VERSION:=11.0.0}"
: "${PYTORCH_ROCM_ARCH:=gfx1200;gfx1201;gfx1100;gfx1101;gfx1102}"
export GPU_FORCE_64BIT_PTR=1
export GPU_MAX_HEAP_SIZE="100%"
export GPU_MAX_ALLOC_PERCENT="100%"
export GPU_USE_SYNC_OBJECTS=1
export PYTORCH_ROCM_ALLOW_UNALIGNED_ACCESS=1
export TORCH_COMMAND="pip install torch==2.8.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.4"
source ~/genai_env/bin/activate
EOF

chmod +x "$INVOKEAI_DIR/setup_env.sh"

success "Base configuration written"

# --- 6. Initialize InvokeAI ---
log "Initializing (model downloads) ..."

# Source environment
source "$INVOKEAI_DIR/setup_env.sh"

# Run InvokeAI configuration
log "Running configuration wizard (downloads several GB) ..."
warn "Press Ctrl+C within 5s to skip" 

# Give user a chance to cancel
sleep 5

invokeai-configure --yes --default_only || {
        warn "Configuration interrupted or failed"
        log "Retry later with: invokeai-configure"
}

success "Initialization complete"

# --- 7. Create Launch Scripts ---
log "Creating launch scripts..."

# Web UI launch script
cat > "$INVOKEAI_DIR/launch_webui.sh" << 'EOF'
#!/bin/bash

echo "🎨 Starting InvokeAI Web Interface"
echo "=================================="

# Setup environment
source "$HOME/InvokeAI/setup_env.sh"

# Navigate to InvokeAI directory
cd "$INVOKEAI_ROOT"

echo "Starting InvokeAI Web UI..."
echo "Access the interface at: http://127.0.0.1:9090"
echo "Use Ctrl+C to stop the server"
echo ""

# Launch InvokeAI web interface
invokeai-web --host 0.0.0.0 --port 9090
EOF

chmod +x "$INVOKEAI_DIR/launch_webui.sh"

# CLI launch script
cat > "$INVOKEAI_DIR/launch_cli.sh" << 'EOF'
#!/bin/bash

echo "💻 Starting InvokeAI Command Line Interface"
echo "==========================================="

# Setup environment
source "$HOME/InvokeAI/setup_env.sh"

# Navigate to InvokeAI directory
cd "$INVOKEAI_ROOT"

echo "Starting InvokeAI CLI..."
echo "Type 'help' for available commands"
echo "Use Ctrl+C or type 'quit' to exit"
echo ""

# Launch InvokeAI CLI
invokeai-batch --interactive
EOF

chmod +x "$INVOKEAI_DIR/launch_cli.sh"

# Model manager script
cat > "$INVOKEAI_DIR/manage_models.sh" << 'EOF'
#!/bin/bash

echo "📦 InvokeAI Model Manager"
echo "========================"

# Setup environment
source "$HOME/InvokeAI/setup_env.sh"

cd "$INVOKEAI_ROOT"

echo "Opening InvokeAI Model Installer..."
echo "This tool helps you download and install models"
echo ""

invokeai-model-install
EOF

chmod +x "$INVOKEAI_DIR/manage_models.sh"

success "Launch scripts created"

# --- 8. Create Desktop Shortcuts (if in GUI environment) ---
if [ ! -z "$DISPLAY" ] || [ ! -z "$WAYLAND_DISPLAY" ]; then
    log "Creating desktop shortcuts..."
    
    # InvokeAI Web UI shortcut
    cat > "$HOME/Desktop/InvokeAI_WebUI.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=InvokeAI Web UI (ROCm)
Comment=Professional AI Image Generation with AMD GPU support
Exec=$INVOKEAI_DIR/launch_webui.sh
Icon=applications-graphics
Terminal=true
Categories=Graphics;Photography;
EOF
    
    chmod +x "$HOME/Desktop/InvokeAI_WebUI.desktop"
    
    # InvokeAI Model Manager shortcut
    cat > "$HOME/Desktop/InvokeAI_Models.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=InvokeAI Model Manager
Comment=Download and manage AI models for InvokeAI
Exec=$INVOKEAI_DIR/manage_models.sh
Icon=package-x-generic
Terminal=true
Categories=System;Settings;
EOF
    
    chmod +x "$HOME/Desktop/InvokeAI_Models.desktop"
    
    success "Desktop shortcuts created"
fi

cd "$HOME"

# --- 9. Performance Tips ---
log "Adding performance tips doc..."

cat > "$INVOKEAI_DIR/PERFORMANCE_TIPS.md" << 'EOF'
# InvokeAI ROCm Performance Tips

## GPU-Specific Settings

### RDNA3 (RX 7000 series)
- HSA_OVERRIDE_GFX_VERSION="11.0.0" (for most RX 7000 cards)
- Use full precision or autocast mixed precision
- Enable attention slicing for large images

### RDNA2 (RX 6000 series)  
- HSA_OVERRIDE_GFX_VERSION="10.3.0"
- May need to use CPU for some operations on older cards

### Memory Optimization
- Lower max_cache_size if you have < 16GB VRAM
- Use tiled decoding for very large images
- Close other GPU applications when generating

## Recommended Settings
- Image Size: Start with 512x512, scale up gradually
- Steps: 20-50 for most models
- Batch Size: 1-4 depending on VRAM
- Use VAE tiling for large images

## Troubleshooting
- If out of memory: reduce image size or batch size
- If slow: check HSA_OVERRIDE_GFX_VERSION setting
- If crashes: try CPU mode for problematic operations
EOF

success "Performance guide created"

headline "Installation Complete"
echo -e "${GREEN}InvokeAI installed successfully${NC}"
echo ""
echo -e "${YELLOW}Quick Start:${NC}"
echo -e "• Web Interface: ${BLUE}$INVOKEAI_DIR/launch_webui.sh${NC}"
echo -e "• Command Line: ${BLUE}$INVOKEAI_DIR/launch_cli.sh${NC}"
echo -e "• Model Manager: ${BLUE}$INVOKEAI_DIR/manage_models.sh${NC}"
echo ""
echo -e "${YELLOW}Web Interface:${NC}"
echo -e "• Start the web UI and go to: ${BLUE}http://127.0.0.1:9090${NC}"
echo -e "• Professional interface with advanced features"
echo -e "• Built-in model management and downloading"
echo ""
echo -e "${YELLOW}Important Directories:${NC}"
echo -e "• InvokeAI Root: ${BLUE}$INVOKEAI_DIR${NC}"
echo -e "• Models: ${BLUE}$INVOKEAI_DIR/models${NC}"
echo -e "• Output Images: ${BLUE}$INVOKEAI_DIR/outputs${NC}"
echo -e "• Configuration: ${BLUE}$INVOKEAI_DIR/invokeai.yaml${NC}"
echo ""
echo -e "${YELLOW}Advanced Features:${NC}"
echo -e "• ControlNet support for guided generation"
echo -e "• Inpainting and outpainting"
echo -e "• Image-to-image transformation"
echo -e "• Batch processing"
echo -e "• Node-based workflow editor"
echo ""
echo -e "${YELLOW}Performance:${NC}"
echo -e "• Check performance tips: ${BLUE}$INVOKEAI_DIR/PERFORMANCE_TIPS.md${NC}"
echo -e "• Monitor GPU usage: ${BLUE}rocm-smi${NC}"
echo -e "• Adjust settings in invokeai.yaml for your GPU"
echo ""
success "Installation completed successfully"
