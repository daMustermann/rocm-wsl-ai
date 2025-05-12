#!/bin/bash

# ==============================================================================
# AI Tools Menu Script for AMD GPUs on WSL2
# Combines functionality of:
# - ROCm/PyTorch installation
# - ComfyUI installation and startup
# - SD.Next installation
# ==============================================================================

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
COMFYUI_DIR="$HOME/ComfyUI"
SDNEXT_DIR="$HOME/SD.Next"
FACEFUSION_UNLOCK_DIR="$HOME/facefusion-unlock"
OOBABOOGA_DIR="$HOME/text-generation-webui"

# Colors for menu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Functions ---

install_rocm_pytorch() {
    echo -e "${YELLOW}[INFO] Running ROCm and PyTorch installation...${NC}"
    echo -e "${BLUE}This will install ROCm, PyTorch and Triton for AMD GPUs${NC}"
    echo -e "${YELLOW}This may take a while...${NC}"
    
    # Run the original script
    ./1_setup_pytorch_rocm_wsl.sh
    
    echo -e "${GREEN}[SUCCESS] ROCm and PyTorch installed!${NC}"
    read -p "Press Enter to continue..."
}

install_comfyui() {
    echo -e "${YELLOW}[INFO] Installing ComfyUI...${NC}"
    
    # Check if ROCm/PyTorch is installed
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        echo -e "${RED}[ERROR] Python virtual environment not found!${NC}"
        echo -e "Please install ROCm and PyTorch first (Option 1)"
        return 1
    fi
    
    # Run the original script
    ./2_install_comfyui.sh
    
    echo -e "${GREEN}[SUCCESS] ComfyUI installed!${NC}"
    read -p "Press Enter to continue..."
}

start_comfyui() {
    echo -e "${YELLOW}[INFO] Starting ComfyUI...${NC}"
    
    # Check if ComfyUI is installed
    if [ ! -f "$COMFYUI_DIR/main.py" ]; then
        echo -e "${RED}[ERROR] ComfyUI not found!${NC}"
        echo -e "Please install ComfyUI first (Option 2)"
        return 1
    fi
    
    # Run the original script
    ./3_start_comfyui.sh
    
    read -p "Press Enter to continue..."
}

install_sdnext() {
    echo -e "${YELLOW}[INFO] Installing SD.Next...${NC}"
    
    # Check if ROCm/PyTorch is installed
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        echo -e "${RED}[ERROR] Python virtual environment not found!${NC}"
        echo -e "Please install ROCm and PyTorch first (Option 1)"
        return 1
    fi
    
    # Run the original script
    ./4_install_sdnext.sh
    
    echo -e "${GREEN}[SUCCESS] SD.Next installed!${NC}"
    read -p "Press Enter to continue..."
}

install_facefusion_unlock() {
    echo -e "${YELLOW}[INFO] Installing facefusion-unlock...${NC}"
    ./5_install_facefusion_unlock.sh
    read -p "Press Enter to continue..."
}

start_facefusion_unlock() {
    echo -e "${YELLOW}[INFO] Starting facefusion-unlock...${NC}"
    ./6_start_facefusion_unlock.sh
    read -p "Press Enter to continue..."
}

install_oobabooga() {
    echo -e "${YELLOW}[INFO] Installing Oobabooga (text-generation-webui)...${NC}"
    ./7_install_oobabooga.sh
    read -p "Press Enter to continue..."
}

start_oobabooga() {
    echo -e "${YELLOW}[INFO] Starting Oobabooga (text-generation-webui)...${NC}"
    ./8_start_oobabooga.sh
    read -p "Press Enter to continue..."
}

start_sdnext() {
    echo -e "${YELLOW}[INFO] Starting SD.Next...${NC}"
    
    # Check if SD.Next is installed
    if [ ! -f "$SDNEXT_DIR/webui.sh" ]; then
        echo -e "${RED}[ERROR] SD.Next not found!${NC}"
        echo -e "Please install SD.Next first (Option 4)"
        return 1
    fi
    
    # Activate environment and start
    source "$VENV_PATH/bin/activate"
    cd "$SDNEXT_DIR"
    ./webui.sh --use-rocm --skip-torch-cuda-test
    
    read -p "Press Enter to continue..."
}

check_status() {
    echo -e "${YELLOW}=== Installation Status ===${NC}"
    
    # Check ROCm/PyTorch
    if [ -f "$VENV_PATH/bin/activate" ]; then
        echo -e "${GREEN}[✓] ROCm/PyTorch installed${NC}"
    else
        echo -e "${RED}[✗] ROCm/PyTorch not installed${NC}"
    fi
    
    # Check ComfyUI
    if [ -f "$COMFYUI_DIR/main.py" ]; then
        echo -e "${GREEN}[✓] ComfyUI installed${NC}"
    else
        echo -e "${RED}[✗] ComfyUI not installed${NC}"
    fi
    
    # Check SD.Next
    if [ -f "$SDNEXT_DIR/webui.sh" ]; then
        echo -e "${GREEN}[✓] SD.Next installed${NC}"
    else
        echo -e "${RED}[✗] SD.Next not installed${NC}"
    fi

    # Check facefusion-unlock
    if [ -f "$FACEFUSION_UNLOCK_DIR/facefusion.py" ]; then
        echo -e "${GREEN}[✓] facefusion-unlock installed${NC}"
    else
        echo -e "${RED}[✗] facefusion-unlock not installed${NC}"
    fi

    # Check Oobabooga
    if [ -f "$OOBABOOGA_DIR/server.py" ]; then
        echo -e "${GREEN}[✓] Oobabooga (text-generation-webui) installed${NC}"
    else
        echo -e "${RED}[✗] Oobabooga (text-generation-webui) not installed${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# --- Main Menu ---

while true; do
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}          AI Tools Menu for WSL2        ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "1. Install ROCm and PyTorch (Required first)"
    echo -e "2. Install ComfyUI"
    echo -e "3. Start ComfyUI"
    echo -e "4. Install SD.Next"
    echo -e "5. Start SD.Next"
    echo -e "${YELLOW}--- FaceFusion ---${NC}"
    echo -e "6. Install facefusion-unlock"
    echo -e "7. Start facefusion-unlock"
    echo -e "${YELLOW}--- LLM Tools ---${NC}"
    echo -e "8. Install Oobabooga (text-generation-webui)"
    echo -e "9. Start Oobabooga (text-generation-webui)"
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -e "S. Check Installation Status"
    echo -e "0. Exit"
    echo -e "${BLUE}========================================${NC}"
    
    read -p "Enter your choice: " choice
    
    case $choice in
        1) install_rocm_pytorch ;;
        2) install_comfyui ;;
        3) start_comfyui ;;
        4) install_sdnext ;;
        5) start_sdnext ;;
        6) install_facefusion_unlock ;;
        7) start_facefusion_unlock ;;
        8) install_oobabooga ;;
        9) start_oobabooga ;;
        S|s) check_status ;;
        0) 
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option!${NC}"
            read -p "Press Enter to continue..."
            ;;
    esac
done
