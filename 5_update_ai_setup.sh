#!/bin/bash

# ==============================================================================
# Update Script for ROCm AI Setup - 2025 Edition
# Updates ROCm, PyTorch, ComfyUI, SD.Next, and other AI tools to latest versions
# ==============================================================================

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
COMFYUI_DIR="$HOME/ComfyUI"
SDNEXT_DIR="$HOME/SD.Next"
AUTOMATIC1111_DIR="$HOME/stable-diffusion-webui"
OLLAMA_DIR="$HOME/ollama"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Functions ---

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_section() {
    echo -e "${CYAN}--- $1 ---${NC}"
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

check_venv() {
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        print_error "Python virtual environment not found at $VENV_PATH"
        print_error "Please run the ROCm/PyTorch setup script first (1_setup_pytorch_rocm_wsl.sh)"
        exit 1
    fi
    source "$VENV_PATH/bin/activate"
    print_success "Virtual environment activated"
}

update_rocm() {
    print_section "Updating ROCm Stack"
    
    print_info "Updating ROCm packages..."
    sudo apt update
    
    # Update ROCm packages
    sudo apt install --only-upgrade -y \
        rocm-dev \
        rocm-libs \
        rocm-utils \
        rocminfo \
        rocm-smi \
        hip-dev \
        miopen-hip \
        rocblas \
        rocsolver \
        rocfft \
        rocsparse \
        rccl \
        2>/dev/null || print_warning "Some ROCm packages not available for upgrade"
    
    # Update mesa drivers (graphics layer)
    print_info "Updating Mesa graphics drivers..."
    sudo apt install --only-upgrade -y \
        mesa-utils \
        mesa-vulkan-drivers \
        vulkan-tools \
        mesa-opencl-icd \
        2>/dev/null || print_warning "Some Mesa packages not available for upgrade"
    
    # Verify ROCm environment
    if [ -f "$HOME/.rocm_env" ]; then
        source "$HOME/.rocm_env"
    fi
    
    print_success "ROCm stack updated"
}
    
    print_warning "AMD GPU driver updates require complete removal and reinstallation"
    print_warning "This will temporarily disable GPU acceleration until complete"
    print_info "This process follows AMD's official update procedure"
    
    read -p "Continue with AMD GPU driver update? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "AMD GPU driver update cancelled"
        return 0
    fi
    
    # Check if AMD driver script exists
    if [ ! -f "./9_install_amd_drivers.sh" ]; then
        print_error "AMD driver installation script not found!"
        print_info "Please ensure 9_install_amd_drivers.sh is in the current directory"
        return 1
    fi
    
    print_info "Starting AMD GPU driver update process..."
    chmod +x ./9_install_amd_drivers.sh
    
    # Run the AMD driver script which will handle the update
    ./9_install_amd_drivers.sh
    
    if [ $? -eq 0 ]; then
        print_success "AMD GPU drivers updated successfully"
        print_warning "Please restart your terminal session"
        print_info "You may need to restart WSL2 for full driver activation"
        
        # Source the new environment
        if [ -f "$HOME/.rocm_env" ]; then
            source "$HOME/.rocm_env"
        fi
        
        print_info "Testing new driver installation..."
        if command -v rocminfo &> /dev/null; then
            print_success "ROCm tools available"
        else
            print_warning "ROCm tools not immediately available - may need terminal restart"
        fi
    else
        print_error "AMD GPU driver update failed"
        return 1
    fi
}

update_pytorch() {
    print_section "Updating PyTorch to latest ROCm-compatible version"
    
    check_venv
    
    # Check current PyTorch version
    print_info "Current PyTorch version:"
    python3 -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'ROCm available: {torch.cuda.is_available()}')" 2>/dev/null || print_warning "PyTorch not installed or not working"
    
    print_info "Installing latest PyTorch with ROCm 6.4 support..."
    pip install --upgrade torch==2.8.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.4
    
    print_info "Updating Triton..."
    pip install -U --pre triton
    
    print_success "PyTorch and Triton updated"
}

update_comfyui() {
    print_section "Updating ComfyUI"
    
    if [ ! -d "$COMFYUI_DIR" ]; then
        print_warning "ComfyUI not found at $COMFYUI_DIR"
        print_info "Checking for ComfyUI in current user's home directory..."
        if [ -d "$HOME/ComfyUI" ]; then
            COMFYUI_DIR="$HOME/ComfyUI"
            print_info "Found ComfyUI at $COMFYUI_DIR"
        else
            print_warning "ComfyUI not found in home directory either"
            return 1
        fi
    fi
    
    check_venv
    
    cd "$COMFYUI_DIR"
    
    print_info "Updating ComfyUI core..."
    git pull
    
    print_info "Updating ComfyUI dependencies..."
    pip install -r requirements.txt --upgrade
    
    # Update ComfyUI Manager if it exists
    if [ -d "custom_nodes/comfyui-manager" ]; then
        print_info "Updating ComfyUI Manager..."
        cd custom_nodes/comfyui-manager
        git pull
        if [ -f "requirements.txt" ]; then
            pip install -r requirements.txt --upgrade
        fi
        cd "$COMFYUI_DIR"
    elif [ -d "custom_nodes/ComfyUI-Manager" ]; then
        print_info "Updating ComfyUI Manager..."
        cd custom_nodes/ComfyUI-Manager
        git pull
        if [ -f "requirements.txt" ]; then
            pip install -r requirements.txt --upgrade
        fi
        cd "$COMFYUI_DIR"
    fi
    
    # Update other custom nodes
    print_info "Updating custom nodes..."
    for node_dir in custom_nodes/*/; do
        if [ -d "$node_dir" ] && [ -d "$node_dir/.git" ]; then
            print_info "Updating $(basename "$node_dir")..."
            cd "$node_dir"
            git pull || print_warning "Failed to update $(basename "$node_dir")"
            if [ -f "requirements.txt" ]; then
                pip install -r requirements.txt --upgrade
            fi
            cd "$COMFYUI_DIR"
        fi
    done
    
    cd "$HOME"
    print_success "ComfyUI updated"
}

update_sdnext() {
    print_section "Updating SD.Next"
    
    # Check multiple possible locations
    SDNEXT_FOUND=""
    if [ -d "$SDNEXT_DIR" ]; then
        SDNEXT_FOUND="$SDNEXT_DIR"
    elif [ -d "$HOME/stable-diffusion-webui-reForge" ]; then
        SDNEXT_FOUND="$HOME/stable-diffusion-webui-reForge"
    elif [ -d "$HOME/automatic" ]; then
        SDNEXT_FOUND="$HOME/automatic"
    elif [ -d "$HOME/stable-diffusion-webui" ]; then
        SDNEXT_FOUND="$HOME/stable-diffusion-webui"
    fi
    
    if [ -z "$SDNEXT_FOUND" ]; then
        print_warning "SD.Next not found in standard locations"
        return 1
    fi
    
    print_info "Found SD.Next at $SDNEXT_FOUND"
    cd "$SDNEXT_FOUND"
    
    print_info "Updating SD.Next..."
    git pull
    
    print_info "Running update script..."
    if [ -f "launch.py" ]; then
        python launch.py --update
    elif [ -f "webui.py" ]; then
        python webui.py --update --exit
    fi
    
    cd "$HOME"
    print_success "SD.Next updated"
}

update_automatic1111() {
    print_section "Updating Automatic1111"
    
    # Check multiple possible locations
    A1111_FOUND=""
    if [ -d "$A1111_DIR" ]; then
        A1111_FOUND="$A1111_DIR"
    elif [ -d "$HOME/stable-diffusion-webui" ]; then
        A1111_FOUND="$HOME/stable-diffusion-webui"
    fi
    
    if [ -z "$A1111_FOUND" ]; then
        print_warning "Automatic1111 not found"
        return 1
    fi
    
    print_info "Found Automatic1111 at $A1111_FOUND"
    cd "$A1111_FOUND"
    
    print_info "Updating Automatic1111..."
    git pull
    
    print_info "Updating requirements..."
    pip install -r requirements.txt --upgrade
    
    cd "$HOME"
    print_success "Automatic1111 updated"
}

update_ollama() {
    print_section "Updating Ollama"
    
    print_info "Updating Ollama..."
    curl -fsSL https://ollama.ai/install.sh | sh
    
    print_info "Restarting Ollama service..."
    sudo systemctl restart ollama
    
    print_success "Ollama updated"
}

update_invokeai() {
    print_section "Updating InvokeAI"
    
    # Check multiple possible locations  
    INVOKEAI_FOUND=""
    if [ -d "$INVOKEAI_DIR" ]; then
        INVOKEAI_FOUND="$INVOKEAI_DIR"
    elif [ -d "$HOME/invokeai" ]; then
        INVOKEAI_FOUND="$HOME/invokeai"
    elif [ -d "$HOME/InvokeAI" ]; then
        INVOKEAI_FOUND="$HOME/InvokeAI"
    fi
    
    if [ -z "$INVOKEAI_FOUND" ]; then
        print_warning "InvokeAI not found"
        return 1
    fi
    
    print_info "Found InvokeAI at $INVOKEAI_FOUND"
    
    # Activate InvokeAI environment
    if [ -f "$INVOKEAI_FOUND/bin/activate" ]; then
        source "$INVOKEAI_FOUND/bin/activate"
    elif [ -f "$INVOKEAI_FOUND/.venv/bin/activate" ]; then
        source "$INVOKEAI_FOUND/.venv/bin/activate"
    fi
    
    print_info "Updating InvokeAI..."
    pip install --upgrade "InvokeAI[xformers]" --extra-index-url https://download.pytorch.org/whl/rocm6.2
    
    print_success "InvokeAI updated"
}

update_amdgpu_drivers() {
    print_section "Updating AMD GPU Drivers"

update_automatic1111() {
    print_section "Updating Automatic1111 WebUI"
    
    if [ ! -d "$AUTOMATIC1111_DIR" ]; then
        print_warning "Automatic1111 WebUI not found at $AUTOMATIC1111_DIR"
        return 1
    fi
    
    cd "$AUTOMATIC1111_DIR"
    
    print_info "Updating Automatic1111 WebUI..."
    git pull
    
    print_info "Updating extensions..."
    for ext_dir in extensions/*/; do
        if [ -d "$ext_dir" ] && [ -d "$ext_dir/.git" ]; then
            print_info "Updating $(basename "$ext_dir")..."
            cd "$ext_dir"
            git pull || print_warning "Failed to update $(basename "$ext_dir")"
            cd "$AUTOMATIC1111_DIR"
        fi
    done
    
    cd "$HOME"
    print_success "Automatic1111 WebUI updated"
}

update_ollama() {
    print_section "Updating Ollama"
    
    if command -v ollama &> /dev/null; then
        print_info "Updating Ollama..."
        curl -fsSL https://ollama.ai/install.sh | sh
        print_success "Ollama updated"
    else
        print_warning "Ollama not installed"
    fi
}

cleanup_cache() {
    print_section "Cleaning up cache and temporary files"
    
    check_venv
    
    print_info "Cleaning pip cache..."
    pip cache purge
    
    print_info "Cleaning apt cache..."
    sudo apt autoremove -y
    sudo apt autoclean
    
    print_success "Cache cleanup completed"
}

verify_installations() {
    print_section "Verifying installations"
    
    check_venv
    
    # ROCm verification
    print_info "ROCm verification:"
    if command -v rocminfo &> /dev/null; then
        rocminfo | grep -E 'Agent [0-9]+|Name:|Marketing Name:' | grep -A2 -B1 'Agent' | grep -v -E 'Host|CPU' | head -5
    else
        print_warning "rocminfo not available"
    fi
    
    # PyTorch verification
    print_info "PyTorch verification:"
    python3 -c "
import torch
print(f'PyTorch Version: {torch.__version__}')
print(f'ROCm Available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'GPU Count: {torch.cuda.device_count()}')
    print(f'GPU Name: {torch.cuda.get_device_name(0)}')
" || print_warning "PyTorch verification failed"
    
    # Triton verification
    print_info "Triton verification:"
    python3 -c "import triton; print(f'Triton Version: {triton.__version__}')" || print_warning "Triton not available"
    
    print_success "Verification completed"
}

show_update_menu() {
    while true; do
        clear
        print_header "AI Tools Update Menu - 2025"
        echo -e "${CYAN}🔄 Choose what to update:${NC}"
        echo ""
        echo -e "1.  ${YELLOW}Update AMD GPU Drivers${NC} (Complete reinstall)"
        echo -e "2.  Update ROCm Stack"
        echo -e "3.  Update PyTorch"
        echo -e "4.  Update ComfyUI"
        echo -e "5.  Update SD.Next"
        echo -e "6.  Update Automatic1111"
        echo -e "7.  Update Ollama"
        echo -e "8.  Update InvokeAI"
        echo ""
        echo -e "9.  ${GREEN}Update All AI Tools${NC} (Skip drivers)"
        echo -e "10. ${RED}Complete System Update${NC} (Drivers + All tools)"
        echo ""
        echo -e "11. Cleanup cache"
        echo -e "12. Verify installations"
        echo -e "0.  Exit"
        echo -e "${BLUE}========================================${NC}"
        
        read -p "Enter your choice: " choice
        
        case $choice in
            1) update_amdgpu_drivers ;;
            2) update_rocm ;;
            3) update_pytorch ;;
            4) update_comfyui ;;
            5) update_sdnext ;;
            6) update_automatic1111 ;;
            7) update_ollama ;;
            8) update_invokeai ;;
            9) 
                print_header "Updating All AI Tools (Skip Drivers)"
                update_pytorch
                update_comfyui
                update_sdnext
                update_automatic1111
                update_ollama
                update_invokeai
                cleanup_cache
                verify_installations
                print_success "All AI tools updated!"
                ;;
            10)
                print_header "Complete System Update"
                print_warning "This will update AMD drivers + all AI tools"
                print_warning "GPU will be temporarily unavailable during driver update"
                read -p "Continue with complete update? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    update_amdgpu_drivers
                    update_pytorch
                    update_comfyui
                    update_sdnext
                    update_automatic1111
                    update_ollama
                    update_invokeai
                    cleanup_cache
                    verify_installations
                    print_success "Complete system update finished!"
                    print_warning "Please restart WSL2 for full driver activation"
                fi
                ;;
            11) cleanup_cache ;;
            12) verify_installations ;;
            0) 
                print_success "Exiting update menu"
                exit 0
                ;;
            *)
                print_error "Invalid option!"
                ;;
        esac
        
        read -p "Press Enter to continue..."
    done
}# --- Main Script ---
echo "Starting AI Tools Update Script..."

# Check if running in WSL
if ! grep -q Microsoft /proc/version; then
    print_warning "This script is designed for WSL2. Some features may not work correctly on native Linux."
fi

show_update_menu
