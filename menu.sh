#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    echo "Error: common.sh not found in lib/" >&2
    exit 1
fi

# ==============================================================================
# ROCm WSL2 AI Toolkit - Main Menu
# Version 2.0.0 - Simplified TUI for ROCm 6.4.2.1 + PyTorch 2.6.0
# ==============================================================================

# Configuration
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
COMFYUI_DIR="$HOME/ComfyUI"
SDNEXT_DIR="$HOME/SD.Next"
AUTOMATIC1111_DIR="$HOME/stable-diffusion-webui"

# Ensure scripts are executable
find "$SCRIPT_DIR/scripts" -type f -name "*.sh" -not -executable -exec chmod +x {} + 2>/dev/null || true

# --- Helper Functions ---

check_venv() {
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        whiptail --title "Environment Not Found" --msgbox "Python virtual environment not found.\n\nPlease install the Base Environment first:\nMain Menu → Install Base Environment" 12 70
        return 1
    fi
    return 0
}

# --- Main Functions ---

install_base() {
    headline "Base Environment Installation"
    
    if ! is_wsl; then
        whiptail --title "WSL2 Required" --msgbox "This installer is designed specifically for WSL2.\n\nFor native Linux, please refer to AMD's official documentation." 10 70
        return
    fi
    
    if (whiptail --title "Confirm Installation" --yesno "Install ROCm 6.4.2.1 + PyTorch 2.6.0?\n\nThis will:\n• Install AMD ROCm 6.4.2.1 via amdgpu-install\n• Create Python virtual environment\n• Install PyTorch 2.6.0 with ROCm support\n• Configure GPU environment\n\nRequires: AMD Adrenalin 25.8.1 on Windows\n\nContinue?" 18 70); then
        "$SCRIPT_DIR/scripts/install/setup_pytorch_rocm.sh"
        
        whiptail --title "Installation Complete" --msgbox "Base environment installation finished!\n\nIMPORTANT: Restart WSL2 now:\n1. Close this terminal\n2. In PowerShell/CMD: wsl --shutdown\n3. Restart Ubuntu\n\nThen you can install AI tools." 14 70
    fi
}

install_tool() {
    local tool_name="$1"
    local install_script="$2"
    local install_dir="$3"
    
    if [ -d "$install_dir" ]; then
        whiptail --title "Already Installed" --msgbox "$tool_name is already installed at:\n$install_dir" 9 70
        return
    fi
    
    if ! check_venv; then return; fi
    
    if [ -f "$install_script" ]; then
        headline "Installing $tool_name"
        "$install_script"
        whiptail --title "Success" --msgbox "$tool_name has been installed successfully!" 8 70
    else
        whiptail --title "Error" --msgbox "Installation script not found:\n$install_script" 9 70
    fi
}

launch_tool() {
    local tool_name="$1"
    local launch_script="$2"
    local check_path="$3"
    
    if [ ! -e "$check_path" ]; then
        whiptail --title "Not Installed" --msgbox "$tool_name is not installed.\n\nPlease install it first from the main menu." 10 70
        return
    fi
    
    if [ -f "$launch_script" ]; then
        headline "Launching $tool_name"
        "$launch_script"
        read -rp "Press Enter to return to menu..."
    else
        whiptail --title "Error" --msgbox "Launch script not found:\n$launch_script" 9 70
    fi
}

show_status() {
    local status_text=""
    
    # System info
    status_text+="=== System Information ===\n"
    if is_wsl; then
        status_text+="Environment: WSL2\n"
    else
        status_text+="Environment: Native Linux\n"
    fi
    status_text+="Ubuntu: $(lsb_release -ds)\n\n"
    
    # ROCm/PyTorch status
    status_text+="=== Base Environment ===\n"
    if [ -f "$VENV_PATH/bin/activate" ]; then
        status_text+="✓ Python venv: INSTALLED\n"
        # shellcheck disable=SC1091
        (
            source "$VENV_PATH/bin/activate"
            PY_VER=$(python3 -c "import torch; print(torch.__version__)" 2>/dev/null || echo "N/A")
            ROCM_OK=$(python3 -c "import torch; print(torch.cuda.is_available())" 2>/dev/null || echo "N/A")
            echo "  PyTorch: $PY_VER"
            echo "  ROCm Available: $ROCM_OK"
        ) >> /tmp/status_check.txt 2>&1
        status_text+=$(cat /tmp/status_check.txt 2>/dev/null || echo "  Status check failed")
        rm -f /tmp/status_check.txt
    else
        status_text+="✗ Base environment: NOT INSTALLED\n"
    fi
    
    # AI Tools status
    status_text+="\n\n=== AI Tools ===\n"
    [ -f "$COMFYUI_DIR/main.py" ] && status_text+="✓ ComfyUI: INSTALLED\n" || status_text+="✗ ComfyUI: NOT INSTALLED\n"
    [ -f "$SDNEXT_DIR/webui.sh" ] && status_text+="✓ SD.Next: INSTALLED\n" || status_text+="✗ SD.Next: NOT INSTALLED\n"
    [ -f "$AUTOMATIC1111_DIR/webui.sh" ] && status_text+="✓ Automatic1111: INSTALLED\n" || status_text+="✗ Automatic1111: NOT INSTALLED\n"
    
    # GPU status
    status_text+="\n=== GPU Information ===\n"
    if command -v rocminfo &> /dev/null; then
        GPU_INFO=$(rocminfo 2>&1 | grep -E "Marketing Name:" | head -1 | sed 's/.*Marketing Name: *//' || echo "Not detected")
        status_text+="GPU: $GPU_INFO\n"
    else
        status_text+="ROCm: NOT INSTALLED\n"
    fi
    
    whiptail --title "System Status" --msgbox "$status_text" 24 70
}

# --- Menu Functions ---

show_install_menu() {
    local CHOICE
    CHOICE=$(whiptail --title "Installation Menu" --menu "Choose what to install:" 16 70 7 \
        "1" "Base Environment (ROCm + PyTorch)" \
        "2" "ComfyUI" \
        "3" "SD.Next" \
        "4" "Automatic1111" \
        "0" "← Back to Main Menu" \
        3>&1 1>&2 2>&3) || return 0
    
    case "$CHOICE" in
        1) install_base ;;
        2) install_tool "ComfyUI" "$SCRIPT_DIR/scripts/install/comfyui.sh" "$COMFYUI_DIR" ;;
        3) install_tool "SD.Next" "$SCRIPT_DIR/scripts/install/sdnext.sh" "$SDNEXT_DIR" ;;
        4) install_tool "Automatic1111" "$SCRIPT_DIR/scripts/install/automatic1111.sh" "$AUTOMATIC1111_DIR" ;;
        0) return ;;
    esac
}

show_launch_menu() {
    local CHOICE
    CHOICE=$(whiptail --title "Launch Menu" --menu "Choose a tool to launch:" 14 70 5 \
        "1" "ComfyUI" \
        "2" "SD.Next" \
        "3" "Automatic1111" \
        "0" "← Back to Main Menu" \
        3>&1 1>&2 2>&3) || return 0
    
    case "$CHOICE" in
        1) launch_tool "ComfyUI" "$SCRIPT_DIR/scripts/start/comfyui.sh" "$COMFYUI_DIR/main.py" ;;
        2) launch_tool "SD.Next" "$SCRIPT_DIR/scripts/start/sdnext.sh" "$SDNEXT_DIR/webui.sh" ;;
        3) launch_tool "Automatic1111" "$SCRIPT_DIR/scripts/start/automatic1111.sh" "$AUTOMATIC1111_DIR/webui.sh" ;;
        0) return ;;
    esac
}

show_help() {
    whiptail --title "Quick Help" --msgbox "\
ROCm WSL2 AI Toolkit v2.0.0

GETTING STARTED:
1. Install Base Environment first
2. Restart WSL2 (wsl --shutdown)
3. Install AI tools
4. Launch your tools!

REQUIREMENTS:
• Windows 11 or Windows 10 with WSL2
• AMD Radeon RX 7000/9000 series GPU
• AMD Adrenalin 25.8.1 driver (Windows)
• Ubuntu 24.04 or 22.04 in WSL2

For detailed setup instructions, see:
docs/WSL2_SETUP_GUIDE.md

For troubleshooting, see:
README.md

AMD Documentation:
rocm.docs.amd.com/projects/radeon-ryzen/" 24 70
}

# --- Main Loop ---

main_menu() {
    while true; do
        CHOICE=$(whiptail --title "ROCm WSL2 AI Toolkit v2.0.0" --menu "\n ROCm 6.4.2.1 | PyTorch 2.6.0 | Ubuntu 24.04/22.04\n\nChoose an option:" 20 70 9 \
            "1" "📦 Install" \
            "2" "🚀 Launch Tool" \
            "3" "📊 System Status" \
            "4" "❓ Help" \
            "5" "🚪 Exit" \
            3>&1 1>&2 2>&3) || {  clear; exit 0; }
        
        case "$CHOICE" in
            1) show_install_menu ;;
            2) show_launch_menu ;;
            3) show_status ;;
            4) show_help ;;
            5) clear; exit 0 ;;
        esac
    done
}

# Start the application
clear
headline "ROCm WSL2 AI Toolkit v2.0.0"
log "ROCm 6.4.2.1 | PyTorch 2.6.0 | WSL2 Ubuntu 24.04/22.04"
echo ""

main_menu