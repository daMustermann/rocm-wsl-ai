#!/bin/bash

# ==============================================================================
# AI Tools Menu Script for AMD GPUs on WSL2 - 2025 Edition
# Enhanced with update capabilities and new AI tools
# Combines functionality of:
# - ROCm/PyTorch installation & updates
# - ComfyUI installation, startup & updates
# - SD.Next installation & startup
# - Automatic1111 WebUI installation & startup
# - Ollama installation & management
# - InvokeAI installation & startup
# - System updates and maintenance
# ==============================================================================

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
COMFYUI_DIR="$HOME/ComfyUI"
SDNEXT_DIR="$HOME/SD.Next"
AUTOMATIC1111_DIR="$HOME/stable-diffusion-webui"
INVOKEAI_DIR="$HOME/InvokeAI"

# Colors for menu
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

install_rocm_pytorch() {
    print_header "Installing ROCm and PyTorch"
    print_info "This will install ROCm 6.3, PyTorch 2.7.1 and Triton for AMD GPUs"
    print_warning "This may take a while and requires WSL restart..."
    
    # Run the original script
    ./1_setup_pytorch_rocm_wsl.sh
    
    print_success "ROCm and PyTorch installed!"
    read -p "Press Enter to continue..."
}

install_comfyui() {
    print_header "Installing ComfyUI"
    
    # Check if ROCm/PyTorch is installed
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        print_error "Python virtual environment not found!"
        print_error "Please install ROCm and PyTorch first (Option 1)"
        return 1
    fi
    
    # Run the original script
    ./2_install_comfyui.sh
    
    print_success "ComfyUI installed!"
    read -p "Press Enter to continue..."
}

start_comfyui() {
    print_header "Starting ComfyUI"
    
    # Check if ComfyUI is installed
    if [ ! -f "$COMFYUI_DIR/main.py" ]; then
        print_error "ComfyUI not found!"
        print_error "Please install ComfyUI first (Installation Menu → Option 2)"
        return 1
    fi
    
    # Run the original script
    ./3_start_comfyui.sh
    
    read -p "Press Enter to continue..."
}

install_sdnext() {
    print_header "Installing SD.Next"
    
    # Check if ROCm/PyTorch is installed
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        print_error "Python virtual environment not found!"
        print_error "Please install ROCm and PyTorch first (Option 1)"
        return 1
    fi
    
    # Run the original script
    ./4_install_sdnext.sh
    
    print_success "SD.Next installed!"
    read -p "Press Enter to continue..."
}

start_sdnext() {
    print_header "Starting SD.Next"
    
    # Check if SD.Next is installed
    if [ ! -f "$SDNEXT_DIR/webui.sh" ]; then
        print_error "SD.Next not found!"
        print_error "Please install SD.Next first (Installation Menu → Option 4)"
        return 1
    fi
    
    # Activate environment and start
    source "$VENV_PATH/bin/activate"
    cd "$SDNEXT_DIR"
    ./webui.sh --use-rocm --skip-torch-cuda-test
    
    read -p "Press Enter to continue..."
}

install_automatic1111() {
    print_header "Installing Automatic1111 WebUI"
    
    # Check if ROCm/PyTorch is installed
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        print_error "Python virtual environment not found!"
        print_error "Please install ROCm and PyTorch first (Option 1)"
        return 1
    fi
    
    ./6_install_automatic1111.sh
    
    print_success "Automatic1111 WebUI installed!"
    read -p "Press Enter to continue..."
}

start_automatic1111() {
    print_header "Starting Automatic1111 WebUI"
    
    if [ ! -f "$AUTOMATIC1111_DIR/webui.sh" ]; then
        print_error "Automatic1111 WebUI not found!"
        print_error "Please install it first (Installation Menu → Option 5)"
        return 1
    fi
    
    cd "$AUTOMATIC1111_DIR"
    ./launch_webui_rocm.sh
    
    read -p "Press Enter to continue..."
}

install_ollama() {
    print_header "Installing Ollama"
    
    ./7_install_ollama.sh
    
    print_success "Ollama installed!"
    read -p "Press Enter to continue..."
}

manage_ollama() {
    print_header "Managing Ollama"
    
    if ! command -v ollama &> /dev/null; then
        print_error "Ollama not found!"
        print_error "Please install Ollama first (Installation Menu → Option 6)"
        return 1
    fi
    
    ~/manage_ollama_models.sh
}

install_invokeai() {
    print_header "Installing InvokeAI"
    
    # Check if ROCm/PyTorch is installed
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        print_error "Python virtual environment not found!"
        print_error "Please install ROCm and PyTorch first (Option 1)"
        return 1
    fi
    
    ./8_install_invokeai.sh
    
    print_success "InvokeAI installed!"
    read -p "Press Enter to continue..."
}

start_invokeai() {
    print_header "Starting InvokeAI"
    
    if [ ! -f "$INVOKEAI_DIR/launch_webui.sh" ]; then
        print_error "InvokeAI not found!"
        print_error "Please install InvokeAI first (Installation Menu → Option 7)"
        return 1
    fi
    
    "$INVOKEAI_DIR/launch_webui.sh"
    
    read -p "Press Enter to continue..."
}

update_system() {
    print_header "System Update"
    
    ./5_update_ai_setup.sh
}

check_status() {
    print_header "Installation Status"
    
    # Check ROCm/PyTorch
    if [ -f "$VENV_PATH/bin/activate" ]; then
        print_success "✓ ROCm/PyTorch installed"
        source "$VENV_PATH/bin/activate"
        python3 -c "import torch; print(f'  - PyTorch: {torch.__version__}'); print(f'  - ROCm available: {torch.cuda.is_available()}')" 2>/dev/null || print_warning "  - PyTorch verification failed"
    else
        print_error "✗ ROCm/PyTorch not installed"
    fi
    
    # Check ComfyUI
    if [ -f "$COMFYUI_DIR/main.py" ]; then
        print_success "✓ ComfyUI installed"
    else
        print_error "✗ ComfyUI not installed"
    fi
    
    # Check SD.Next
    if [ -f "$SDNEXT_DIR/webui.sh" ]; then
        print_success "✓ SD.Next installed"
    else
        print_error "✗ SD.Next not installed"
    fi
    
    # Check Automatic1111
    if [ -f "$AUTOMATIC1111_DIR/webui.sh" ]; then
        print_success "✓ Automatic1111 WebUI installed"
    else
        print_error "✗ Automatic1111 WebUI not installed"
    fi
    
    # Check Ollama
    if command -v ollama &> /dev/null; then
        print_success "✓ Ollama installed"
        if systemctl --user is-active --quiet ollama.service 2>/dev/null; then
            print_success "  - Service running"
        else
            print_warning "  - Service not running"
        fi
    else
        print_error "✗ Ollama not installed"
    fi
    
    # Check InvokeAI
    if [ -f "$INVOKEAI_DIR/launch_webui.sh" ]; then
        print_success "✓ InvokeAI installed"
    else
        print_error "✗ InvokeAI not installed"
    fi
    
    # Check ROCm system status
    echo ""
    print_info "ROCm System Status:"
    if command -v rocminfo &> /dev/null; then
        rocminfo | grep -E 'Agent [0-9]+|Name:|Marketing Name:' | grep -A2 -B1 'Agent' | grep -v -E 'Host|CPU' | head -3
    else
        print_warning "rocminfo not available"
    fi
    
    read -p "Press Enter to continue..."
}

show_installation_menu() {
    while true; do
        clear
        print_header "AI Tools Installation Menu"
        echo -e "1.  ${YELLOW}Install AMD GPU Drivers${NC} (Graphics + ROCm)"
        echo -e "2.  ${YELLOW}Install ROCm and PyTorch${NC} (Required foundation)"
        echo -e "3.  Install ComfyUI"
        echo -e "4.  Install SD.Next" 
        echo -e "5.  Install Automatic1111 WebUI"
        echo -e "6.  Install Ollama (Local AI Chat)"
        echo -e "7.  Install InvokeAI (Professional AI Art)"
        echo -e "8.  Check Installation Status"
        echo -e "0.  Back to Main Menu"
        echo -e "${BLUE}========================================${NC}"
        
        read -p "Enter your choice: " choice
        
        case $choice in
            1) 
                print_info "Starting AMD GPU driver installation..."
                if [ -f "./9_install_amd_drivers.sh" ]; then
                    chmod +x ./9_install_amd_drivers.sh
                    ./9_install_amd_drivers.sh
                    read -p "Press Enter to continue..."
                else
                    print_error "AMD driver installation script not found!"
                    read -p "Press Enter to continue..."
                fi
                ;;
            2) install_rocm_pytorch ;;
            3) install_comfyui ;;
            4) install_sdnext ;;
            5) install_automatic1111 ;;
            6) install_ollama ;;
            7) install_invokeai ;;
            8) check_status ;;
            0) return ;;
            *)
                print_error "Invalid option!"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

show_startup_menu() {
    while true; do
        clear
        print_header "AI Tools Startup Menu"
        echo -e "1.  Start ComfyUI"
        echo -e "2.  Start SD.Next"
        echo -e "3.  Start Automatic1111 WebUI"
        echo -e "4.  Start Ollama Chat"
        echo -e "5.  Manage Ollama Models"
        echo -e "6.  Start InvokeAI"
        echo -e "7.  Check All Services Status"
        echo -e "0.  Back to Main Menu"
        echo -e "${BLUE}========================================${NC}"
        
        read -p "Enter your choice: " choice
        
        case $choice in
            1) start_comfyui ;;
            2) start_sdnext ;;
            3) start_automatic1111 ;;
            4) 
                if command -v ollama &> /dev/null; then
                    ~/start_ollama_chat.sh
                else
                    print_error "Ollama not installed!"
                fi
                read -p "Press Enter to continue..."
                ;;
            5) manage_ollama ;;
            6) start_invokeai ;;
            7) check_status ;;
            0) return ;;
            *)
                print_error "Invalid option!"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# --- Main Menu ---

while true; do
    clear
    print_header "AI Tools Suite for WSL2 - 2025 Edition"
    echo -e "${CYAN}🚀 Enhanced AMD GPU AI Development Environment${NC}"
    echo ""
    echo -e "📦 ${GREEN}Installation${NC}"
    echo -e "1.  Installation Menu (Install AI Tools)"
    echo ""
    echo -e "▶️  ${BLUE}Startup${NC}"
    echo -e "2.  Startup Menu (Launch AI Tools)"
    echo ""
    echo -e "🔄 ${YELLOW}Maintenance${NC}"
    echo -e "3.  Update System (Update all tools + AMD drivers)"
    echo -e "4.  Check Installation Status"
    echo ""
    echo -e "📊 ${PURPLE}Quick Actions${NC}"
    echo -e "5.  Start ComfyUI (Quick)"
    echo -e "6.  Start Ollama Chat (Quick)"
    echo ""
    echo -e "🔧 ${RED}Advanced${NC}"
    echo -e "7.  AMD Driver Management (Install/Update)"
    echo ""
    echo -e "0.  Exit"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${CYAN}💡 Tip: AMD drivers need complete reinstall for updates!${NC}"
    
    read -p "Enter your choice: " choice
    
    case $choice in
        1) show_installation_menu ;;
        2) show_startup_menu ;;
        3) update_system ;;
        4) check_status ;;
        5) start_comfyui ;;
        6) 
            if command -v ollama &> /dev/null; then
                ~/start_ollama_chat.sh
            else
                print_error "Ollama not installed! Use Installation Menu → Option 6 to install."
            fi
            read -p "Press Enter to continue..."
            ;;
        7)
            print_info "Starting AMD Driver Management..."
            if [ -f "./9_install_amd_drivers.sh" ]; then
                chmod +x ./9_install_amd_drivers.sh
                ./9_install_amd_drivers.sh
                read -p "Press Enter to continue..."
            else
                print_error "AMD driver script not found!"
                read -p "Press Enter to continue..."
            fi
            ;;
        0) 
            print_success "Thank you for using AI Tools Suite!"
            print_info "Happy AI development! 🎨🤖"
            exit 0
            ;;
        *)
            print_error "Invalid option!"
            read -p "Press Enter to continue..."
            ;;
    esac
done