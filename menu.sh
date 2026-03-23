#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# ROCm WSL2 AI Toolkit - Main Menu
# Version 2.2.0 - Styled with Gum ✨
# ==============================================================================

# Check for gum dependency
if ! command -v gum >/dev/null 2>&1; then
    echo -e "\033[0;35mThis toolkit uses 'gum' for its gorgeous new Terminal UI.\033[0m"
    read -p "Install gum now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null
        sudo apt update && sudo apt install -y gum
    else
        echo "Gum is required for the new UI. Exiting."
        exit 1
    fi
fi

# Source common utilities (now gum-aware)
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    echo "Error: common.sh not found in lib/" >&2
    exit 1
fi

# Configuration
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
COMFYUI_DIR="$HOME/ComfyUI"
SDNEXT_DIR="$HOME/SD.Next"
AUTOMATIC1111_DIR="$HOME/stable-diffusion-webui"

# Ensure scripts are executable
find "$SCRIPT_DIR/scripts" -type f -name "*.sh" -not -executable -exec chmod +x {} + 2>/dev/null || true

# --- Shared Checks ---

check_venv() {
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        msgbox "Environment Not Found" "Python virtual environment not found.\n\nPlease install the Base Environment first:\nMain Menu → Install Base Environment"
        return 1
    fi
    return 0
}

# --- Main Functions ---

install_base() {
    headline "Base Environment Installation"
    
    if ! is_wsl; then
        msgbox "WSL2 Required" "This installer is designed specifically for WSL2.\n\nFor native Linux, please refer to AMD's official documentation."
        return
    fi
    
    if yesno "Confirm Installation" "Install ROCm 7.2.0 + PyTorch 2.9.1?\n\nThis will:\n• Install AMD ROCm 7.2.0 via amdgpu-install\n• Create Python virtual environment\n• Install PyTorch 2.9.1 with ROCm support\n• Configure GPU environment\n\nRequires: AMD Adrenalin 26.1.1 on Windows"; then
        "$SCRIPT_DIR/scripts/install/setup_pytorch_rocm.sh"
        
        msgbox "Installation Complete" "Base environment installation finished!\n\nIMPORTANT: Restart WSL2 now:\n1. Close this terminal\n2. In PowerShell/CMD: wsl --shutdown\n3. Restart Ubuntu\n\nThen you can install AI tools."
    fi
}

install_tool() {
    local tool_name="$1"
    local install_script="$2"
    local install_dir="$3"
    
    if [ -d "$install_dir" ]; then
        msgbox "Already Installed" "$tool_name is already installed at:\n$install_dir"
        return
    fi
    
    if ! check_venv; then return; fi
    
    if [ -f "$install_script" ]; then
        headline "Installing $tool_name"
        "$install_script"
        msgbox "Success" "$tool_name has been installed successfully!"
        
        # Prompt for shortcut immediately after installation
        if yesno "Create Desktop Shortcut?" "Would you like to automatically create a Windows Desktop shortcut for $tool_name?"; then
            "$SCRIPT_DIR/scripts/utils/create_shortcut.sh" "$tool_name" "$SCRIPT_DIR/scripts/start/$(basename "$install_script")"
        fi
    else
        msgbox "Error" "Installation script not found:\n$install_script"
    fi
}

launch_tool() {
    local tool_name="$1"
    local launch_script="$2"
    local check_path="$3"
    
    if [ ! -e "$check_path" ]; then
        msgbox "Not Installed" "$tool_name is not installed.\n\nPlease install it first from the main menu."
        return
    fi
    
    if [ -f "$launch_script" ]; then
        headline "Launching $tool_name"
        "$launch_script"
        echo ""
        read -rp "Press Enter to return to menu..."
    else
        msgbox "Error" "Launch script not found:\n$launch_script"
    fi
}

show_status() {
    local sys_info=""
    local py_info=""
    local tool_info=""
    local gpu_info=""
    
    # OS & Processing
    local wsl_env="Native Linux"
    if is_wsl; then wsl_env="WSL2"; fi
    local os_ver=$(lsb_release -ds || echo "Unknown Linux")
    local cpu_info=$(grep -m 1 "model name" /proc/cpuinfo | awk -F': ' '{print $2}' | xargs || echo "Unknown CPU")
    local ram_gb=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo || echo "0")
    
    sys_info+="Environment: $(gum style --foreground 212 "$wsl_env")\n"
    sys_info+="Ubuntu Ver : $os_ver\n"
    sys_info+="CPU Model  : $cpu_info\n"
    sys_info+="WSL RAM    : ${ram_gb} GB"

    # Base Environment
    if [ -f "$VENV_PATH/bin/activate" ]; then
        py_info+="Venv Status : $(gum style --foreground 46 INSTALLED)\n"
        # shellcheck disable=SC1091
        local python_status
        python_status=$(source "$VENV_PATH/bin/activate" && python3 -c "
import torch
py_ver = torch.__version__
rocm_ok = '✓ True' if torch.cuda.is_available() else '✗ False'
color = '46' if torch.cuda.is_available() else '196'
print(f'PyTorch Ver : {py_ver}')
print(f'ROCm Active : \033[38;5;{color}m{rocm_ok}\033[0m')
" 2>/dev/null || echo "Status check failed")
        py_info+="$python_status"
    else
        py_info+="Venv Status : $(gum style --foreground 196 "NOT INSTALLED")\n"
        py_info+="ROCm Active : -"
    fi

    # AI Tools
    local c_status=$( [ -f "$COMFYUI_DIR/main.py" ] && gum style --foreground 46 "✓ Installed" || gum style --foreground 240 "✗ Missing" )
    local s_status=$( [ -f "$SDNEXT_DIR/webui.sh" ] && gum style --foreground 46 "✓ Installed" || gum style --foreground 240 "✗ Missing" )
    local a_status=$( [ -f "$AUTOMATIC1111_DIR/webui.sh" ] && gum style --foreground 46 "✓ Installed" || gum style --foreground 240 "✗ Missing" )
    
    tool_info+="ComfyUI       : $c_status\n"
    tool_info+="SD.Next       : $s_status\n"
    tool_info+="Automatic1111 : $a_status"

    # GPU Hardware
    if command -v rocminfo &> /dev/null; then
        local marketing_name=$(rocminfo 2>&1 | grep -E "Marketing Name:" | grep -i "Radeon" | head -1 | sed 's/.*Marketing Name: *//' | xargs || echo "Not detected")
        if [ "$marketing_name" != "Not detected" ] && [ -n "$marketing_name" ]; then
            local raw_vram=$(rocminfo 2>&1 | awk '/Marketing Name:.*Radeon/{found=1} found && /Pool 1/{in_pool=1} in_pool && /Size:/{print $2; exit}' | cut -d'(' -f1)
            local vram_gb="Unknown"
            if [ -n "$raw_vram" ] && [[ "$raw_vram" =~ ^[0-9]+$ ]]; then
                vram_gb=$(awk "BEGIN {printf \"%.1f\", $raw_vram/1024/1024}")
            fi
            gpu_info+="Device : $(gum style --foreground 214 "$marketing_name")\n"
            gpu_info+="VRAM   : $(gum style --foreground 214 "${vram_gb} GB")"
        else
            gpu_info+="Device : $(gum style --foreground 196 "No AMD GPU Detected")"
        fi
    else
        gpu_info+="ROCm   : $(gum style --foreground 196 "NOT INSTALLED")"
    fi

    # Layout using gum style to create beautiful bordered sections
    clear
    echo ""
    gum style --bold --margin "0 2" --foreground 212 "📊 System Status Dashboard"
    echo ""
    
    local left_col=$(gum join --vertical \
        "$(echo -e "$(gum style --bold --foreground 63 "💻 Host System")\n\n$sys_info" | gum style --border rounded --border-foreground 63 --padding "0 2" --width 50)" \
        "$(echo -e "$(gum style --bold --foreground 212 "🎨 Installed AI Tools")\n\n$tool_info" | gum style --border rounded --border-foreground 212 --padding "0 2" --width 50)")
        
    local right_col=$(gum join --vertical \
        "$(echo -e "$(gum style --bold --foreground 214 "🎮 AMD GPU Hardware")\n\n$gpu_info" | gum style --border rounded --border-foreground 214 --padding "0 2" --width 45)" \
        "$(echo -e "$(gum style --bold --foreground 46 "🐍 Python Environment")\n\n$py_info" | gum style --border rounded --border-foreground 46 --padding "0 2" --width 45)")
        
    gum join --horizontal "$left_col" "  " "$right_col" | gum style --margin "0 2"
    
    echo ""
    read -rp "  Press Enter to return to menu..."
}

# --- Menu Functions ---

show_install_menu() {
    local CHOICE
    CHOICE=$(gum choose --cursor="» " --header="Choose what to install:" \
        "1. Base Environment (ROCm + PyTorch)" \
        "2. ComfyUI" \
        "3. SD.Next" \
        "4. Automatic1111" \
        "0. ← Back to Main Menu")
    
    case "$CHOICE" in
        1.*) install_base ;;
        2.*) install_tool "ComfyUI" "$SCRIPT_DIR/scripts/install/comfyui.sh" "$COMFYUI_DIR" ;;
        3.*) install_tool "SD.Next" "$SCRIPT_DIR/scripts/install/sdnext.sh" "$SDNEXT_DIR" ;;
        4.*) install_tool "Automatic1111" "$SCRIPT_DIR/scripts/install/automatic1111.sh" "$AUTOMATIC1111_DIR" ;;
        0.*) return ;;
    esac
}

show_launch_menu() {
    local CHOICE
    CHOICE=$(gum choose --cursor="» " --header="Choose a tool to launch:" \
        "1. ComfyUI" \
        "2. SD.Next" \
        "3. Automatic1111" \
        "0. ← Back to Main Menu")
    
    case "$CHOICE" in
        1.*) launch_tool "ComfyUI" "$SCRIPT_DIR/scripts/start/comfyui.sh" "$COMFYUI_DIR/main.py" ;;
        2.*) launch_tool "SD.Next" "$SCRIPT_DIR/scripts/start/sdnext.sh" "$SDNEXT_DIR/webui.sh" ;;
        3.*) launch_tool "Automatic1111" "$SCRIPT_DIR/scripts/start/automatic1111.sh" "$AUTOMATIC1111_DIR/webui.sh" ;;
        0.*) return ;;
    esac
}

show_shortcuts_menu() {
    local options=()
    [ -f "$COMFYUI_DIR/main.py" ] && options+=("ComfyUI")
    [ -f "$SDNEXT_DIR/webui.sh" ] && options+=("SD.Next")
    [ -f "$AUTOMATIC1111_DIR/webui.sh" ] && options+=("Automatic1111")
    options+=("0. ← Back to Main Menu")

    if [ ${#options[@]} -eq 1 ]; then
        msgbox "No Tools Installed" "You need to install at least one AI tool before creating shortcuts."
        return
    fi

    local CHOICE
    CHOICE=$(gum choose --cursor="» " --header="Create Desktop Shortcut for:" "${options[@]}")

    case "$CHOICE" in
        "ComfyUI") "$SCRIPT_DIR/scripts/utils/create_shortcut.sh" "ComfyUI" "$SCRIPT_DIR/scripts/start/comfyui.sh" ;;
        "SD.Next") "$SCRIPT_DIR/scripts/utils/create_shortcut.sh" "SD.Next" "$SCRIPT_DIR/scripts/start/sdnext.sh" ;;
        "Automatic1111") "$SCRIPT_DIR/scripts/utils/create_shortcut.sh" "Automatic1111" "$SCRIPT_DIR/scripts/start/automatic1111.sh" ;;
        "0."*) return ;;
    esac
}

show_help() {
    msgbox "Quick Help" "ROCm WSL2 AI Toolkit v2.2.0\n\n$(gum style --bold GETTING STARTED:)\n1. Install Base Environment first\n2. Restart WSL2 (wsl --shutdown)\n3. Install AI tools\n4. Launch your tools!\n\n$(gum style --bold REQUIREMENTS:)\n• Windows 11 or Windows 10 with WSL2\n• AMD Radeon RX 7000/9000 series GPU\n• AMD Adrenalin 26.1.1 driver (Windows)\n• Ubuntu 24.04 or 22.04 in WSL2\n\nFor detailed setup instructions, see:\ndocs/WSL2_SETUP_GUIDE.md\n\nFor troubleshooting, see:\nREADME.md\n\nAMD Documentation:\nrocm.docs.amd.com/projects/radeon-ryzen/"
}

# --- Main Loop ---

main_menu() {
    while true; do
        clear
        echo ""
        gum style --border double --margin "0 2" --padding "1 2" --border-foreground 212 --align center "$(gum style --bold --foreground 212 "ROCm WSL2 AI Toolkit v2.2.0")" "ROCm 7.2.0 | PyTorch 2.9.1 | WSL2 Ubuntu 24.04/22.04"
        echo ""
        
        CHOICE=$(gum choose --cursor="» " --header="$(gum style --bold 'Main Menu') (Choose an option):" \
            "1. 📦 Install Tools" \
            "2. 🚀 Launch Tool" \
            "3. 🔗 Create Desktop Shortcuts" \
            "4. 📊 System Status" \
            "5. ✨ Magic Settings Auto-Tuner" \
            "6. ❓ Help" \
            "0. 🚪 Exit")
        
        case "$CHOICE" in
            1.*) show_install_menu ;;
            2.*) show_launch_menu ;;
            3.*) show_shortcuts_menu ;;
            4.*) show_status ;;
            5.*) "$SCRIPT_DIR/scripts/utils/auto_tuner.sh" ;;
            6.*) show_help ;;
            0.*) clear; exit 0 ;;
        esac
    done
}

# Start the application
main_menu