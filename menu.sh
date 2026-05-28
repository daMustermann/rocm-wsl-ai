#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# ROCm WSL2 AI Toolkit - Main Menu
# Version 3.1.0 - ROCDXG + Gum ✨
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

# Initialise and load persistent user settings (GPU profile, port overrides, …)
ensure_user_env
load_user_env

# Source first-run wizard (defines first_run_check)
if [ -f "$SCRIPT_DIR/scripts/utils/first_run.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/utils/first_run.sh"
fi

# Source GPU diagnostics (defines run_gpu_diag)
if [ -f "$SCRIPT_DIR/scripts/utils/gpu_diag.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/scripts/utils/gpu_diag.sh"
fi

# Configuration
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
COMFYUI_DIR="$HOME/ComfyUI"
SDNEXT_DIR="$HOME/SD.Next"
AUTOMATIC1111_DIR="$HOME/stable-diffusion-webui"
KOHYA_DIR="$HOME/kohya_ss"
KOHYA_VENV="$HOME/kohya_env"

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
    
    if yesno "Confirm Installation" "Install ROCm 7.2.3 + ROCDXG + PyTorch 2.9.1?\n\nThis will:\n• Install AMD ROCm 7.2.3 via official quick-start\n• Build & install ROCDXG (librocdxg) for WSL GPU compute\n• Create Python virtual environment\n• Install PyTorch 2.9.1 with ROCm support\n• Configure GPU environment\n\nRequires:\n• AMD Adrenalin 26.2.2+ on Windows\n• Windows SDK installed on Windows"; then
        "$SCRIPT_DIR/scripts/install/setup_pytorch_rocm.sh"
        
        msgbox "Installation Complete" "Base environment installation finished!\n\nIMPORTANT: Restart WSL2 now:\n1. Close this terminal\n2. In PowerShell/CMD: wsl --shutdown\n3. Restart Ubuntu\n\nThen you can install AI tools."
    fi
}

upgrade_base() {
    headline "Upgrade to ROCm 7.2.3 + ROCDXG"
    
    if ! is_wsl; then
        msgbox "WSL2 Required" "This upgrader is designed specifically for WSL2."
        return
    fi
    
    if [ -f "$SCRIPT_DIR/scripts/install/upgrade_to_rocdxg.sh" ]; then
        "$SCRIPT_DIR/scripts/install/upgrade_to_rocdxg.sh"
        
        msgbox "Upgrade Complete" "Your environment has been upgraded to ROCm 7.2.3 + ROCDXG!\n\nIMPORTANT: Restart WSL2 now:\n1. Close this terminal\n2. In PowerShell/CMD: wsl --shutdown\n3. Restart Ubuntu\n\nYour AI tools and models were NOT touched.\nOnly Python dependencies were reinstalled."
    else
        msgbox "Error" "Upgrade script not found:\n$SCRIPT_DIR/scripts/install/upgrade_to_rocdxg.sh"
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
    local k_status=$( [ -d "$KOHYA_DIR" ] && gum style --foreground 46 "✓ Installed" || gum style --foreground 240 "✗ Missing" )
    
    tool_info+="ComfyUI       : $c_status\n"
    tool_info+="SD.Next       : $s_status\n"
    tool_info+="Automatic1111 : $a_status\n"
    tool_info+="kohya_ss      : $k_status"

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
        "2. ⬆️  Upgrade from ROCm 7.2.1 → 7.2.3 (ROCDXG)" \
        "3. ComfyUI" \
        "4. SD.Next" \
        "5. Automatic1111" \
        "6. 🎨 kohya_ss (LoRA / Model Training)" \
        "0. ← Back to Main Menu")
    
    case "$CHOICE" in
        1.*) install_base ;;
        2.*) upgrade_base ;;
        3.*) install_tool "ComfyUI" "$SCRIPT_DIR/scripts/install/comfyui.sh" "$COMFYUI_DIR" ;;
        4.*) install_tool "SD.Next" "$SCRIPT_DIR/scripts/install/sdnext.sh" "$SDNEXT_DIR" ;;
        5.*) install_tool "Automatic1111" "$SCRIPT_DIR/scripts/install/automatic1111.sh" "$AUTOMATIC1111_DIR" ;;
        6.*) install_kohya_ss ;;
        0.*) return ;;
    esac
}

# kohya_ss has its own dedicated venv (kohya_env) and does NOT require genai_env.
# Therefore it cannot use the generic install_tool() which enforces check_venv.
install_kohya_ss() {
    if [ -d "$KOHYA_DIR" ]; then
        msgbox "Already Installed" "kohya_ss is already installed at:\n$KOHYA_DIR\n\nTo update it: Updates → Update Installed AI Tools → kohya_ss"
        return
    fi

    if ! is_wsl; then
        msgbox "WSL2 Required" "kohya_ss installation requires WSL2."
        return
    fi

    if [ -f "$SCRIPT_DIR/scripts/install/kohya_ss.sh" ]; then
        headline "Installing kohya_ss"
        "$SCRIPT_DIR/scripts/install/kohya_ss.sh"
        msgbox "Success" "kohya_ss has been installed successfully!\n\nGUI starts at: http://localhost:7861\nLaunch via: Main Menu → Launch Tool → kohya_ss"

        if yesno "Create Desktop Shortcut?" "Would you like to create a Windows Desktop shortcut for kohya_ss?"; then
            "$SCRIPT_DIR/scripts/utils/create_shortcut.sh" "kohya_ss" "$SCRIPT_DIR/scripts/start/kohya_ss.sh"
        fi
    else
        msgbox "Error" "Installation script not found:\n$SCRIPT_DIR/scripts/install/kohya_ss.sh"
    fi
}

show_launch_menu() {
    local CHOICE
    CHOICE=$(gum choose --cursor="» " --header="Choose a tool to launch:" \
        "1. ComfyUI" \
        "2. SD.Next" \
        "3. Automatic1111" \
        "4. 🎨 kohya_ss (Training GUI)" \
        "0. ← Back to Main Menu")
    
    case "$CHOICE" in
        1.*) launch_tool "ComfyUI" "$SCRIPT_DIR/scripts/start/comfyui.sh" "$COMFYUI_DIR/main.py" ;;
        2.*) launch_tool "SD.Next" "$SCRIPT_DIR/scripts/start/sdnext.sh" "$SDNEXT_DIR/webui.sh" ;;
        3.*) launch_tool "Automatic1111" "$SCRIPT_DIR/scripts/start/automatic1111.sh" "$AUTOMATIC1111_DIR/webui.sh" ;;
        4.*) launch_tool "kohya_ss" "$SCRIPT_DIR/scripts/start/kohya_ss.sh" "$KOHYA_DIR" ;;
        0.*) return ;;
    esac
}

show_shortcuts_menu() {
    local options=()
    [ -f "$COMFYUI_DIR/main.py" ] && options+=("ComfyUI")
    [ -f "$SDNEXT_DIR/webui.sh" ] && options+=("SD.Next")
    [ -f "$AUTOMATIC1111_DIR/webui.sh" ] && options+=("Automatic1111")
    [ -d "$KOHYA_DIR" ] && options+=("kohya_ss")
    options+=("0. ← Back to Main Menu")

    if [ ${#options[@]} -eq 1 ]; then
        msgbox "No Tools Installed" "You need to install at least one AI tool before creating shortcuts."
        return
    fi

    local CHOICE
    CHOICE=$(gum choose --cursor="» " --header="Create Desktop Shortcut for:" "${options[@]}")

    case "$CHOICE" in
        "ComfyUI")      "$SCRIPT_DIR/scripts/utils/create_shortcut.sh" "ComfyUI"      "$SCRIPT_DIR/scripts/start/comfyui.sh" ;;
        "SD.Next")      "$SCRIPT_DIR/scripts/utils/create_shortcut.sh" "SD.Next"      "$SCRIPT_DIR/scripts/start/sdnext.sh" ;;
        "Automatic1111") "$SCRIPT_DIR/scripts/utils/create_shortcut.sh" "Automatic1111" "$SCRIPT_DIR/scripts/start/automatic1111.sh" ;;
        "kohya_ss")     "$SCRIPT_DIR/scripts/utils/create_shortcut.sh" "kohya_ss"     "$SCRIPT_DIR/scripts/start/kohya_ss.sh" ;;
        "0."*) return ;;
    esac
}

show_help() {
    msgbox "Quick Help" "ROCm WSL2 AI Toolkit v3.2.0\n\n$(gum style --bold GETTING STARTED:)\n1. Install Base Environment first\n2. Restart WSL2 (wsl --shutdown)\n3. Install AI tools\n4. Launch your tools!\n\n$(gum style --bold AI TOOLS:)\n• ComfyUI — Node-based Stable Diffusion workflow\n• SD.Next / Automatic1111 — WebUI for Stable Diffusion\n• kohya_ss — LoRA, DreamBooth \u0026 model training (optional)\n\n$(gum style --bold UPGRADING:)\nInstall Tools → Upgrade from ROCm 7.2.1 → 7.2.3\nFor toolkit updates: Updates menu → Check for Toolkit Updates\n\n$(gum style --bold REQUIREMENTS:)\n• Windows 11\n• AMD Radeon RX 7000/9000 series GPU\n  or Ryzen Strix / Strix Halo APU\n• AMD Adrenalin 26.2.2+ driver (Windows)\n• Windows SDK (for ROCDXG build)\n• Ubuntu 24.04 or 22.04 in WSL2\n\nFor detailed setup instructions, see:\ndocs/WSL2_SETUP_GUIDE.md\n\nAMD Documentation:\nrocm.docs.amd.com/projects/radeon-ryzen/"
}

# --- Changelog helper (used by self-update) ---

_show_update_changenotes() {
    # Display the topmost version section from CHANGELOG.md in a gum pager.
    # Called after a successful git pull so the user sees what changed.
    command -v gum >/dev/null 2>&1 || return 0
    local cl="$SCRIPT_DIR/CHANGELOG.md"
    [ -f "$cl" ] || return 0

    # Extract from the first ## [...] header up to (but not including) the second
    local notes
    notes=$(awk '/^## \[/{c++; if(c==2) exit} c==1{print}' "$cl")
    [ -z "$notes" ] && return 0

    echo ""
    gum style --bold --foreground 212 --margin "0 2" "📋 What changed in this update:"
    echo ""
    echo "$notes" | gum pager --soft-wrap
}

# --- Settings Menu ---

# _list_rocm_gpus: prints "IDX|Marketing Name|gfx_arch" for each GPU agent
_list_rocm_gpus() {
    command -v rocminfo >/dev/null 2>&1 || return 1
    export HSA_ENABLE_DXG_DETECTION=1
    local rocm_out
    rocm_out=$(rocminfo 2>/dev/null) || return 1

    local gpu_idx=0
    while IFS='|' read -r mkt gfx; do
        [ -z "$gfx" ] && continue
        echo "${gpu_idx}|${mkt}|${gfx}"
        ((gpu_idx++)) || true
    done < <(echo "$rocm_out" | awk '
        /^Agent [0-9]+/ {
            if (is_gpu && gfx != "") printf "%s|%s\n", mkt, gfx
            is_gpu=0; mkt=""; gfx=""
        }
        /Device Type:.*GPU/ { is_gpu=1 }
        /Marketing Name:/ {
            sub(/.*Marketing Name:[[:space:]]*/, "")
            sub(/[[:space:]]*$/, "")
            mkt=$0
        }
        /^[[:space:]]+Name:[[:space:]]+gfx[0-9]+/ {
            match($0, /gfx[0-9]+/)
            gfx=substr($0, RSTART, RLENGTH)
        }
        END { if (is_gpu && gfx != "") printf "%s|%s\n", mkt, gfx }
    ')
}

show_gpu_profile_menu() {
    headline "GPU Profile Selection"

    # Reload current saved values
    load_user_env
    local cur_gfx="${HSA_OVERRIDE_GFX_VERSION:-}"
    local cur_dev="${ROCR_VISIBLE_DEVICES:-}"

    local status_line
    if [ -z "$cur_gfx" ] && [ -z "$cur_dev" ]; then
        status_line="Current: $(gum style --foreground 46 "Auto-detect (default)")"
    else
        status_line="Current: GFX=$(gum style --foreground 214 "${cur_gfx:-auto}")   DEVICE=$(gum style --foreground 214 "${cur_dev:-all}")"
    fi
    echo "  $status_line"
    echo ""

    # Build GPU list from rocminfo
    local -a gpu_labels=() gpu_gfx_list=() gpu_idx_list=()
    while IFS='|' read -r idx mkt gfx; do
        gpu_labels+=("GPU ${idx}: ${mkt:-Unknown} (${gfx})")
        gpu_gfx_list+=("$gfx")
        gpu_idx_list+=("$idx")
    done < <(_list_rocm_gpus 2>/dev/null)

    local -a choices=()
    choices+=("🔄 Auto — let ROCm detect the GPU automatically (recommended)")
    for lbl in "${gpu_labels[@]:-}"; do
        [ -n "$lbl" ] && choices+=("$lbl")
    done
    choices+=("✏️  Manual — enter HSA_OVERRIDE_GFX_VERSION manually")
    choices+=("0. ← Back")

    local CHOICE
    CHOICE=$(gum choose --cursor="» " --header="Select GPU profile:" "${choices[@]}")

    case "$CHOICE" in
        "🔄 Auto"*)
            _update_user_env "HSA_OVERRIDE_GFX_VERSION" ""
            _update_user_env "ROCR_VISIBLE_DEVICES" ""
            export HSA_OVERRIDE_GFX_VERSION=""
            export ROCR_VISIBLE_DEVICES=""
            msgbox "Auto-detect restored" "GPU settings cleared.\nROCm will auto-detect the GPU architecture on next launch."
            ;;
        "GPU "*)
            # Match selected label to stored arrays
            local i selected_gfx="" selected_idx=-1
            for i in "${!gpu_labels[@]}"; do
                if [ "${gpu_labels[$i]}" = "$CHOICE" ]; then
                    selected_gfx="${gpu_gfx_list[$i]}"
                    selected_idx="${gpu_idx_list[$i]}"
                    break
                fi
            done
            if [ -n "$selected_gfx" ]; then
                _update_user_env "HSA_OVERRIDE_GFX_VERSION" "$selected_gfx"
                _update_user_env "ROCR_VISIBLE_DEVICES" "$selected_idx"
                export HSA_OVERRIDE_GFX_VERSION="$selected_gfx"
                export ROCR_VISIBLE_DEVICES="$selected_idx"
                msgbox "GPU Profile Saved" "Active GPU : GPU $selected_idx\nArchitecture: $selected_gfx\nROCR_VISIBLE_DEVICES: $selected_idx\n\nSettings stored in ~/.config/rocm-wsl-ai/user.env\nAll launch scripts will use this profile."
            fi
            ;;
        "✏️  Manual"*)
            local manual_gfx
            manual_gfx=$(gum input \
                --placeholder "e.g. gfx1100 or gfx1200" \
                --value "${cur_gfx}" \
                --header "Enter HSA_OVERRIDE_GFX_VERSION (leave empty = auto):")
            _update_user_env "HSA_OVERRIDE_GFX_VERSION" "$manual_gfx"
            export HSA_OVERRIDE_GFX_VERSION="$manual_gfx"
            if [ -n "$manual_gfx" ]; then
                msgbox "Manual Override Saved" "HSA_OVERRIDE_GFX_VERSION='$manual_gfx'\nStored in user.env."
            else
                _update_user_env "ROCR_VISIBLE_DEVICES" ""
                export ROCR_VISIBLE_DEVICES=""
                msgbox "Cleared" "HSA_OVERRIDE_GFX_VERSION cleared — auto-detect active."
            fi
            ;;
        "0."*) return ;;
    esac
}

show_settings_editor() {
    while true; do
        load_user_env  # always reflect latest saved values
        local cur_gfx="${HSA_OVERRIDE_GFX_VERSION:-}"
        local cur_dev="${ROCR_VISIBLE_DEVICES:-}"
        local cur_dxg="${HSA_ENABLE_DXG_DETECTION:-1}"
        local cur_cfy="${COMFYUI_PORT:-}"
        local cur_sdn="${SDNEXT_PORT:-}"
        local cur_a11="${A1111_PORT:-}"
        local cur_koy="${KOHYA_PORT:-}"

        local CHOICE
        CHOICE=$(gum choose --cursor="» " \
            --header="Edit Settings  (empty value = use default):" \
            "1. HSA_OVERRIDE_GFX_VERSION   [${cur_gfx:-auto}]" \
            "2. ROCR_VISIBLE_DEVICES       [${cur_dev:-all GPUs}]" \
            "3. HSA_ENABLE_DXG_DETECTION   [${cur_dxg:-1}]" \
            "4. ComfyUI Port               [${cur_cfy:-8188}]" \
            "5. SD.Next Port               [${cur_sdn:-7860}]" \
            "6. Automatic1111 Port         [${cur_a11:-7860}]" \
            "7. kohya_ss Port              [${cur_koy:-7861}]" \
            "8. 📁 Open user.env in editor" \
            "0. ← Back")

        local val
        case "$CHOICE" in
            1.*)
                val=$(gum input --value "$cur_gfx" \
                      --placeholder "gfx1100 | gfx1102 | gfx1200 | empty=auto" \
                      --header "GPU Architecture (HSA_OVERRIDE_GFX_VERSION):")
                _update_user_env "HSA_OVERRIDE_GFX_VERSION" "$val"
                export HSA_OVERRIDE_GFX_VERSION="$val"
                ;;
            2.*)
                val=$(gum input --value "$cur_dev" \
                      --placeholder "0 | 1 | 0,1 | empty=all" \
                      --header "GPU Device Index for multi-GPU (ROCR_VISIBLE_DEVICES):")
                _update_user_env "ROCR_VISIBLE_DEVICES" "$val"
                export ROCR_VISIBLE_DEVICES="$val"
                ;;
            3.*)
                val=$(gum input --value "${cur_dxg:-1}" \
                      --placeholder "1 = enabled (WSL requires this)" \
                      --header "WSL DXCore bridge (HSA_ENABLE_DXG_DETECTION):")
                _update_user_env "HSA_ENABLE_DXG_DETECTION" "${val:-1}"
                export HSA_ENABLE_DXG_DETECTION="${val:-1}"
                ;;
            4.*)
                val=$(gum input --value "${cur_cfy:-8188}" --placeholder "8188" \
                      --header "ComfyUI Port:")
                _update_user_env "COMFYUI_PORT" "$val"; export COMFYUI_PORT="$val"
                ;;
            5.*)
                val=$(gum input --value "${cur_sdn:-7860}" --placeholder "7860" \
                      --header "SD.Next Port:")
                _update_user_env "SDNEXT_PORT" "$val"; export SDNEXT_PORT="$val"
                ;;
            6.*)
                val=$(gum input --value "${cur_a11:-7860}" --placeholder "7860" \
                      --header "Automatic1111 Port:")
                _update_user_env "A1111_PORT" "$val"; export A1111_PORT="$val"
                ;;
            7.*)
                val=$(gum input --value "${cur_koy:-7861}" --placeholder "7861" \
                      --header "kohya_ss Port:")
                _update_user_env "KOHYA_PORT" "$val"; export KOHYA_PORT="$val"
                ;;
            8.*)
                local ed="${EDITOR:-}"
                if [ -z "$ed" ]; then
                    command -v nano >/dev/null 2>&1 && ed=nano
                    command -v vi   >/dev/null 2>&1 && ed=vi
                fi
                if [ -n "$ed" ]; then
                    "$ed" "$USER_ENV"
                else
                    msgbox "No editor found" "Set EDITOR or install nano:\n  sudo apt install nano\nThen open: $USER_ENV"
                fi
                ;;
            0.*) return ;;
        esac
    done
}

show_settings_menu() {
    while true; do
        local CHOICE
        CHOICE=$(gum choose --cursor="» " --header="⚙️  Settings:" \
            "1. 🎮 GPU Profile  (select active GPU / fix arch detection)" \
            "2. ✏️  Edit Settings  (ports, env vars, user.env)" \
            "3. 🔍 GPU Diagnostics" \
            "0. ← Back to Main Menu")

        case "$CHOICE" in
            1.*) show_gpu_profile_menu ;;
            2.*) show_settings_editor ;;
            3.*) run_gpu_diag ;;
            0.*) return ;;
        esac
    done
}

# --- Self-Update & Updates Menu ---

self_update_toolkit() {
    headline "Toolkit Self-Update Check"

    if [ ! -d "$SCRIPT_DIR/.git" ]; then
        msgbox "Not a Git Repository" "Self-update requires a git clone.\n\nTo update manually:\n  git -C '$SCRIPT_DIR' pull"
        return
    fi

    log "Fetching remote update information..."
    if ! git -C "$SCRIPT_DIR" fetch origin 2>/dev/null; then
        msgbox "Network Error" "Could not reach the remote repository.\nPlease check your internet connection."
        return
    fi

    local branch behind
    branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    behind=$(git -C "$SCRIPT_DIR" rev-list "HEAD..origin/$branch" --count 2>/dev/null || echo "0")

    if [ "$behind" = "0" ]; then
        msgbox "Already Up to Date" "✅ The toolkit is already up to date!\n\nNo new commits on origin/$branch."
        return
    fi

    local changelog
    changelog=$(git -C "$SCRIPT_DIR" log "HEAD..origin/$branch" --oneline --no-merges 2>/dev/null | head -15)

    if yesno "Updates Available ($behind new commit(s))" "New changes:\n\n$changelog\n\nApply updates now? (git pull --rebase)"; then
        if git -C "$SCRIPT_DIR" pull --rebase --autostash; then
            _show_update_changenotes
            msgbox "Update Complete" "✅ Toolkit updated successfully!\n\nPlease restart menu.sh to apply all changes:\n  Press Ctrl+C, then run: ./menu.sh"
        else
            msgbox "Update Failed" "❌ git pull failed.\n\nTry manually:\n  git -C '$SCRIPT_DIR' pull"
        fi
    fi
}

show_updates_menu() {
    while true; do
        local CHOICE
        CHOICE=$(gum choose --cursor="» " --header="🔄 Updates:" \
            "1. 🔄 Check for Toolkit Updates (git pull)" \
            "2. 🛠️  Update Installed AI Tools" \
            "0. ← Back to Main Menu")

        case "$CHOICE" in
            1.*) self_update_toolkit ;;
            2.*) "$SCRIPT_DIR/scripts/utils/update_ai_setup.sh" ;;
            0.*) return ;;
        esac
    done
}

# --- Main Loop ---

main_menu() {
    while true; do
        clear
        echo ""
        gum style --border double --margin "0 2" --padding "1 2" --border-foreground 212 --align center "$(gum style --bold --foreground 212 "ROCm WSL2 AI Toolkit v3.2.0")" "ROCm 7.2.3 + ROCDXG | PyTorch 2.9.1 | WSL2 Ubuntu 24.04/22.04"
        echo ""
        
        CHOICE=$(gum choose --cursor="» " --header="$(gum style --bold 'Main Menu') (Choose an option):" \
            "1. 📦 Install Tools" \
            "2. 🚀 Launch Tool" \
            "3. 🔗 Create Desktop Shortcuts" \
            "4. 📊 System Status" \
            "5. ✨ Magic Settings Auto-Tuner" \
            "6. 🔄 Updates" \
            "7. ⚙️  Settings" \
            "8. ❓ Help" \
            "0. 🚪 Exit")
        
        case "$CHOICE" in
            1.*) show_install_menu ;;
            2.*) show_launch_menu ;;
            3.*) show_shortcuts_menu ;;
            4.*) show_status ;;
            5.*) "$SCRIPT_DIR/scripts/utils/auto_tuner.sh" ;;
            6.*) show_updates_menu ;;
            7.*) show_settings_menu ;;
            8.*) show_help ;;
            0.*) clear; exit 0 ;;
        esac
    done
}

# --- Startup Checks ---
check_windows_sdk_warning() {
    if is_wsl && ! has_windows_sdk; then
        echo ""
        if command -v gum >/dev/null 2>&1; then
            echo -e "$(gum style --bold --foreground 196 '[!] Missing Windows SDK')\n\nROCm 7.2.3 on WSL requires the Windows SDK to build ROCDXG.\nWe could not detect it in the default system path.\n\n\e[1mPlease install it on Windows before proceeding.\e[0m\nDownload: https://aka.ms/winsdk\n\n\e[3m(If you installed it to a custom drive, the installer might not find it, in which case you can ignore this warning)\e[0m" | gum style --border rounded --margin "0 2" --padding "1 2" --border-foreground 196
        else
            echo -e "${RED}[MISSING WINDOWS SDK]${NC}"
            echo -e "ROCm 7.2.3 on WSL requires the Windows SDK to build ROCDXG."
            echo -e "Download it here: https://aka.ms/winsdk"
        fi
        echo ""
        read -rp "  Press Enter to acknowledge and continue..."
    fi
}

# Detect old ROCm installation and show upgrade guidance
check_upgrade_needed() {
    # Only show notice if ROCm is installed but ROCDXG is not
    if has_rocm && ! has_rocdxg; then
        local old_rocm="unknown"
        if [ -f "/opt/rocm/.info/version" ]; then
            old_rocm=$(cat /opt/rocm/.info/version 2>/dev/null | head -1 | tr -cd '0-9.' | head -1)
        fi
        
        local amd_url="https://amd.com/support"
        local winsdk_url="https://aka.ms/winsdk"
        
        echo ""
        if command -v gum >/dev/null 2>&1; then
            echo -e "\e[1;38;5;214m[!] Upgrade Available\e[0m\n\nYour system has ROCm ${old_rocm} without ROCDXG.\nAMD now requires ROCDXG (librocdxg) for WSL GPU compute.\n\n\e[1mTo upgrade:\e[0m\n  Main Menu → Install Tools → Upgrade from ROCm 7.2.1 → 7.2.3\n\n\e[1mWhat you need on Windows:\e[0m\n  • AMD Adrenalin 26.2.2+ driver\n    \e[4m${amd_url}\e[0m\n  • Windows SDK\n    \e[4m${winsdk_url}\e[0m\n\n\e[38;5;46mYour AI tools and models will NOT be affected.\e[0m" | gum style --border rounded --margin "0 2" --padding "1 2" --border-foreground 214
        else
            echo -e "${YELLOW}[UPGRADE AVAILABLE]${NC} ROCm ${old_rocm} detected without ROCDXG."
            echo -e "${YELLOW}AMD now requires ROCDXG for WSL GPU compute.${NC}"
            echo -e "Go to: Install Tools → Upgrade from ROCm 7.2.1 → 7.2.3"
            echo -e ""
            echo -e "What you need on Windows:"
            echo -e "  • AMD Adrenalin 26.2.2+ driver: ${amd_url}"
            echo -e "  • Windows SDK: ${winsdk_url}"
        fi
        echo ""
        read -rp "  Press Enter to continue to menu..."
    fi
}

# Run startup checks before showing menu
first_run_check  2>/dev/null || true   # welcome wizard on very first launch
check_windows_sdk_warning
check_upgrade_needed

# Start the application
main_menu