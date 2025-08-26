#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    echo "common.sh not found in lib/" >&2; exit 1
fi

# ==============================================================================
# AI Tools Suite for AMD GPUs on Linux & WSL2 - 2025 (TUI with whiptail)
# - Always latest ROCm & PyTorch Nightly
# - Image & Video Generation: ComfyUI, SD.Next, Automatic1111, InvokeAI, Fooocus, SD WebUI Forge
# - Utilities: Setup/Updates, GitHub self-update, Removal routines
# ==============================================================================

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
COMFYUI_DIR="$HOME/ComfyUI"
SDNEXT_DIR="$HOME/SD.Next"
AUTOMATIC1111_DIR="$HOME/stable-diffusion-webui"
INVOKEAI_DIR="$HOME/InvokeAI"
FOOOCUS_DIR="$HOME/Fooocus"
FORGE_DIR="$HOME/stable-diffusion-webui-forge"
REPO_REMOTE="origin"
POST_UPDATE_FLAG="/tmp/.ai_suite_post_update_flag"

# --- Helpers ---
# Map legacy function names to common.sh helpers for minimal diff
print_header(){ headline "$@"; }
print_success(){ success "$@"; }
print_warning(){ warn "$@"; }
print_error(){ err "$@"; }
print_info(){ log "$@"; }

ensure_scripts_executable() {
    if find "$SCRIPT_DIR/scripts" -type f -name "*.sh" -not -executable -print -quit | grep -q '.'; then
        print_info "Making scripts executable..."
        find "$SCRIPT_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} +
        print_success "Scripts are now executable."
    fi
}

# --- Prerequisite Checks ---
check_venv() {
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        whiptail --title "Environment Not Found" --msgbox "The Python virtual environment was not found.\n\nPlease run the 'Base Installation' first:\nManage Tools -> Install -> Base Installation (ROCm & PyTorch)" 12 78
        return 1
    fi
    return 0
}

# --- Tool-specific Functions ---
install_rocm_pytorch() {
    local ROCM_VERSION
    ROCM_VERSION=$(whiptail --title "ROCm Version Select" --menu "Choose which ROCm version to install for the base environment." 16 78 2 \
        "latest" "Latest stable ROCm (recommended) + PyTorch for ROCm 6.1 Nightly" \
        "7.0-rc1" "Experimental ROCm 7.0-rc1 + PyTorch for ROCm 7.0 Nightly" \
        3>&1 1>&2 2>&3) || return 0

    print_header "Installing ROCm and PyTorch (${ROCM_VERSION})"
    print_info "This will install the selected ROCm version, PyTorch Nightly, and Triton."
    print_warning "This may take a while and might require a system restart..."

    ./scripts/install/setup_pytorch_rocm.sh "${ROCM_VERSION}"

    whiptail --title "Installation Finished" --msgbox "ROCm and PyTorch (${ROCM_VERSION}) installation script has finished.\n\nA system restart is highly recommended." 10 78
}

install_tool() {
    local tool_name="$1"
    local install_script="$2"
    local install_dir="$3"

    if [ -n "$install_dir" ] && [ -d "$install_dir" ]; then
        whiptail --msgbox "$tool_name is already installed at: $install_dir" 8 78
        return
    fi

    if ! check_venv; then return; fi

    if [ -f "$install_script" ]; then
        print_header "Installing $tool_name"
        "$install_script"
        whiptail --title "Success" --msgbox "$tool_name has been installed." 8 78
    else
        whiptail --title "Error" --msgbox "Installation script not found:\n$install_script" 8 78
    fi
}

start_tool() {
    local tool_name="$1"
    local start_script="$2"
    local install_check_path="$3"

    if [ ! -e "$install_check_path" ]; then
        whiptail --title "Not Found" --msgbox "$tool_name does not appear to be installed.\nCannot find: $install_check_path" 10 78
        return
    fi

    if [ -f "$start_script" ]; then
        print_header "Starting $tool_name"
        "$start_script"
    else
        whiptail --title "Error" --msgbox "Start script not found:\n$start_script" 8 78
    fi
    read -p "Press Enter to return to the menu..."
}

remove_tool_dir() {
    local dir="$1"; local name="$2"
    if [ -d "$dir" ]; then
        if (whiptail --title "Confirm Removal" --yesno "Are you sure you want to remove $name?\n\nThis will permanently delete the directory:\n$dir" 12 78); then
            rm -rf "$dir" && whiptail --msgbox "$name has been removed." 8 78 || whiptail --msgbox "Error: Failed to remove $name." 8 78
        fi
    else
        whiptail --msgbox "$name is not installed (directory not found)." 8 78
    fi
}

# --- System & Update Functions ---
update_ai_stack() {
    print_header "Updating AI Stack"
    print_info "This will update ROCm, PyTorch, and all installed AI tools."
    if [ -f "./scripts/utils/update_ai_setup.sh" ]; then
        ./scripts/utils/update_ai_setup.sh
        whiptail --title "Finished" --msgbox "AI Stack update process has finished." 8 78
    else
        whiptail --title "Error" --msgbox "Update script not found:\n./scripts/utils/update_ai_setup.sh" 8 78
    fi
}

self_update_repo() {
    print_header "Checking for script updates..."
    if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        whiptail --title "Not a Git Repository" --msgbox "This installation was not cloned from Git. Cannot self-update." 8 78
        return 1
    fi

    print_info "Fetching remote updates..."
    git fetch --all --prune || { whiptail --msgbox "git fetch failed. Check your connection." 8 78; return 1; }

    UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "${REPO_REMOTE}/main")
    if [[ "$UPSTREAM" == "${REPO_REMOTE}/main" ]]; then
        print_warning "No upstream branch is set. Defaulting to '${UPSTREAM}' for update comparison."
    fi
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse "$UPSTREAM" 2>/dev/null || echo "")
    BASE=$(git merge-base @ "$UPSTREAM" 2>/dev/null || echo "")

    if [ -z "$REMOTE" ] || [ -z "$BASE" ]; then
        whiptail --title "Update Warning" --msgbox "Could not determine remote version. A manual 'git pull' may be required." 8 78
        return 1
    fi

    if [ "$LOCAL" = "$REMOTE" ]; then
        return 0 # 0 signifies up-to-date
    elif [ "$LOCAL" = "$BASE" ]; then
        print_info "Updates available for the menu script. Pulling..."
        git pull --rebase --autostash || git pull --autostash || { whiptail --msgbox "git pull failed. Please resolve conflicts manually." 8 78; return 1; }

        touch "$POST_UPDATE_FLAG"

        whiptail --msgbox "Update successful! The script will now restart to continue the process." 8 78
        exec "$0" "$@" # Restart the script
    elif [ "$REMOTE" = "$BASE" ]; then
        whiptail --title "Local Commits" --msgbox "You have local commits. A manual 'git pull' is recommended before updating." 8 78
        return 1
    else
        whiptail --title "Diverged History" --msgbox "Local and remote histories have diverged. Please resolve manually." 8 78
        return 1
    fi
}

run_full_update() {
    print_header "Starting Full Update Process"

    # self_update_repo will restart if it finds an update, or return 0 if up-to-date, 1 on other conditions.
    if self_update_repo; then
        # This code is reached only if the script was already up-to-date.
        print_info "Menu script is already up-to-date."
        if (whiptail --title "Update AI Stack" --yesno "Do you want to proceed with updating the full AI stack (ROCm, PyTorch, Tools)?" 12 78); then
            update_ai_stack
        else
            whiptail --msgbox "AI Stack update cancelled." 8 78
        fi
    else
        # This is reached if self_update_repo returned 1 (e.g. local commits, error)
        whiptail --msgbox "Script update could not proceed. Aborting AI stack update." 10 78
    fi
}

check_status() {
    local status_text
    status_text=$(
        # Check ROCm/PyTorch
        echo "--- System Status ---"
        if [ -f "$VENV_PATH/bin/activate" ]; then
            echo "✓ ROCm/PyTorch Environment: INSTALLED"
            # Source in a subshell to not pollute the main script's env
            (
                # shellcheck disable=SC1091
                source "$VENV_PATH/bin/activate"

                PY_VER=$(python3 -c "import torch; print(torch.__version__)" 2>/dev/null || echo "N/A")
                ROCM_OK=$(python3 -c "import torch; print(torch.cuda.is_available())" 2>/dev/null || echo "N/A")
                echo "  - PyTorch Version: $PY_VER"
                echo "  - ROCm Detected by PyTorch: $ROCM_OK"
            ) || echo "  - PyTorch verification failed."
        else
            echo "✗ ROCm/PyTorch Environment: NOT INSTALLED"
        fi

        # Check Tools
        echo -e "\n--- Tool Status ---"
        [ -f "$COMFYUI_DIR/main.py" ] && echo "✓ ComfyUI: INSTALLED" || echo "✗ ComfyUI: NOT INSTALLED"
        [ -f "$SDNEXT_DIR/webui.sh" ] && echo "✓ SD.Next: INSTALLED" || echo "✗ SD.Next: NOT INSTALLED"
        [ -f "$AUTOMATIC1111_DIR/webui.sh" ] && echo "✓ Automatic1111: INSTALLED" || echo "✗ Automatic1111: NOT INSTALLED"
        [ -f "$INVOKEAI_DIR/invoke.sh" ] && echo "✓ InvokeAI: INSTALLED" || echo "✗ InvokeAI: NOT INSTALLED"
        [ -d "$FOOOCUS_DIR" ] && echo "✓ Fooocus: INSTALLED" || echo "✗ Fooocus: NOT INSTALLED"
        [ -d "$FORGE_DIR" ] && echo "✓ SD WebUI Forge: INSTALLED" || echo "✗ SD WebUI Forge: NOT INSTALLED"

        # Check ROCm system status
        echo -e "\n--- GPU Information ---"
        if command -v rocminfo &> /dev/null; then
            rocminfo | grep -E 'Agent [0-9]+|Name:|Marketing Name:' | grep -A2 -B1 'Agent' | grep -v -E 'Host|CPU' | head -3
        else
            echo "rocminfo command not found. Is ROCm installed correctly?"
        fi
    )
    whiptail --title "Installation Status" --msgbox "$status_text" 24 78
}

# --- Menus ---
get_latest_rocm_version() {
    log "Fetching latest ROCm version number from repo.radeon.com..."
    # Fetches directory listing, extracts version-like folders (e.g., 6.1.2/),
    # filters out any non-standard ones, sorts them by version, and gets the latest.
    # We ignore anything with letters (e.g., rc, beta, alpha) to get the latest stable.
    local latest_version
    latest_version=$(curl -s "https://repo.radeon.com/rocm/apt/" | \
        grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?/' | \
        sed 's/\///' | \
        sort -V | \
        tail -n 1)

    if [ -z "$latest_version" ]; then
        err "Could not determine latest ROCm version. Aborting."
        err "Please check your internet connection or the AMD repository status."
        return 1
    fi
    echo "$latest_version"
    return 0
}

get_latest_rc_version() {
    log "Fetching latest ROCm RC version number from repo.radeon.com..."
    local latest_rc_version
    # Regex updated to be more flexible for RC versions like '7.0_rc1'
    latest_rc_version=$(curl -s "https://repo.radeon.com/rocm/apt/" | \
        grep -oE '[0-9]+\.[0-9]+_rc[0-9a-zA-Z.-]+/' | \
        sed 's/\///' | \
        sort -V | \
        tail -n 1)

    if [ -z "$latest_rc_version" ]; then
        echo ""
        return 1
    fi
    echo "$latest_rc_version"
    return 0
}

manage_gpu_drivers() {
    headline "AMD GPU Driver Management"
    local latest_rocm_version rocm_rc_version
    if ! latest_rocm_version=$(get_latest_rocm_version); then
        whiptail --title "Error" --msgbox "Failed to fetch the latest stable ROCm version. Please check the logs and your internet connection." 10 78
        return
    fi
    success "Latest stable ROCm version found: ${latest_rocm_version}"

    rocm_rc_version=$(get_latest_rc_version)
    if [ -n "$rocm_rc_version" ]; then
        success "Latest RC ROCm version found: ${rocm_rc_version}"
    fi

    local menu_options=()
    menu_options+=("${latest_rocm_version}" "Latest stable version (recommended)")
    if [ -n "$rocm_rc_version" ]; then
        menu_options+=("${rocm_rc_version}" "Latest Release Candidate (experimental)")
    fi

    local rocm_version_to_install
    rocm_version_to_install=$(whiptail --title "Select ROCm Version" --menu "Choose which ROCm version to install." 16 78 2 "${menu_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$rocm_version_to_install" ]; then
        whiptail --msgbox "Installation cancelled." 8 78
        return
    fi

    success "Selected ROCm version for installation: ${rocm_version_to_install}"

    local rocm_version_installed
    # Use dpkg-query for a more robust check that doesn't exit on error
    rocm_version_installed=$(dpkg-query -W -f='${Version}' rocm-dev 2>/dev/null || echo "")

    local prompt_msg
    if [ -n "$rocm_version_installed" ]; then
        if [ "$rocm_version_installed" == "$rocm_version_to_install" ]; then
            prompt_msg="You already have the selected ROCm version (${rocm_version_to_install}) installed.\n\nDo you want to force a reinstallation?"
        else
            prompt_msg="An existing ROCm installation was found (v${rocm_version_installed}).\nYou have chosen to install v${rocm_version_to_install}.\n\nThis will REMOVE the old version and install the new one. Your AI tools may need updates afterwards.\n\nProceed with update?"
        fi
    else
        prompt_msg="No existing ROCm installation was found.\n\nThis will install the selected ROCm version (${rocm_version_to_install}).\n\nDo you want to proceed with the installation?"
    fi

    if !(whiptail --title "Confirm Installation" --yesno "$prompt_msg" 18 78); then
        whiptail --msgbox "Installation cancelled." 8 78
        return
    fi

    # --- Removal ---
    if [ -n "$rocm_version_installed" ]; then
        (
        echo 0; echo "XXX"; echo "Removing existing AMD/ROCm packages (this may take a moment)..."; echo "XXX"
        # Use uninstall procedure from official docs
        sudo apt autoremove -y rocm rocm-core &>/dev/null
        echo 50; echo "XXX"; echo "Cleaning up old repository files..."; echo "XXX"
        sudo rm -f /etc/apt/sources.list.d/rocm.list /etc/apt/sources.list.d/rocm-graphics.list /etc/apt/preferences.d/rocm-pin-600
        echo 75; echo "XXX"; echo "Updating package lists..."; echo "XXX"
        sudo apt update &>/dev/null
        echo 100
        ) | whiptail --title "Removing Old Drivers" --gauge "Please wait..." 8 78 0
    fi

    # --- Installation ---
    (
        local CODENAME
        CODENAME=$(lsb_release -cs)

        echo 0 "Updating package lists..."
        sudo apt-get update -y &>/dev/null

        echo 10 "Installing prerequisites (curl, gnupg)..."
        ensure_apt_packages curl gnupg2 &>/dev/null

        echo 20 "Adding AMD repository key (per official docs)..."
        sudo mkdir --parents --mode=0755 /etc/apt/keyrings
        curl -sL https://repo.radeon.com/rocm/rocm.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/rocm.gpg

        echo 30 "Adding ROCm repositories for version ${rocm_version_to_install}..."
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${rocm_version_to_install} ${CODENAME} main" | sudo tee /etc/apt/sources.list.d/rocm.list > /dev/null
        # Add graphics repository as per official ROCm 7.0 docs
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/apt/${rocm_version_to_install} ${CODENAME} main" | sudo tee /etc/apt/sources.list.d/rocm-graphics.list > /dev/null

        echo 40 "Setting APT pinning..."
        echo -e 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' | sudo tee /etc/apt/preferences.d/rocm-pin-600 > /dev/null

        echo 50 "Updating package lists with new repositories..."
        sudo apt-get update -y &>/dev/null

        echo 60 "Installing ROCm meta-package..."
        # Use the rocm meta-package as per official docs
        sudo apt-get install -y --no-install-recommends rocm &>/dev/null

        echo 90 "Configuring user permissions..."
        sudo usermod -a -G render,video "$USER"
        echo 'SUBSYSTEM=="kfd", KERNEL=="kfd", GROUP="render", MODE="0666"' | sudo tee /etc/udev/rules.d/70-rocm.rules >/dev/null
        echo 'SUBSYSTEM=="drm", KERNEL=="renderD*", GROUP="render", MODE="0666"' | sudo tee -a /etc/udev/rules.d/70-rocm.rules >/dev/null
        sudo udevadm control --reload-rules &>/dev/null
        sudo udevadm trigger &>/dev/null

        echo 100 "Installation script finished."
        sleep 1
    ) | whiptail --title "Installing ROCm ${rocm_version_to_install}" --gauge "Please wait, this will take several minutes..." 10 78 0

    # --- Environment Setup ---
    headline "Configuring Environment"
    local ROCM_ENV_FILE="$HOME/.rocm_env"
    log "Creating ROCm environment file at ${ROCM_ENV_FILE}..."
    cat > "$ROCM_ENV_FILE" <<- EOF
# ROCm Environment Configuration (auto-generated by AI Tools Suite)
export ROCM_PATH=/opt/rocm
export PATH=\$ROCM_PATH/bin:\$ROCM_PATH/llvm/bin:\$PATH
export LD_LIBRARY_PATH=\$ROCM_PATH/lib:\$LD_LIBRARY_PATH
export HIP_PATH=\$ROCM_PATH
export ROCM_VERSION=${rocm_version_to_install}

# Source auto-detected GPU environment if available
[ -f "\$HOME/.config/rocm-wsl-ai/gpu.env" ] && source "\$HOME/.config/rocm-wsl-ai/gpu.env"
EOF
    success "ROCm environment file created."

    if ! grep -q "source.*\.rocm_env" "$HOME/.bashrc"; then
        log "Adding ROCm environment to ~/.bashrc..."
        echo -e '\n# ROCm Environment\n[ -f ~/.rocm_env ] && source ~/.rocm_env' >> "$HOME/.bashrc"
        success "Added source command to ~/.bashrc."
    fi

    # --- Testing ---
    headline "Verifying Installation"
    log "Sourcing new environment for test..."
    # shellcheck source=/dev/null
    source "$ROCM_ENV_FILE"

    local test_results="Installation script finished. Let's verify it.\n\n"
    if ! command -v rocminfo &> /dev/null; then
        test_results+="ERROR: 'rocminfo' command not found.\nInstallation likely failed. Please check the logs."
    else
        local rocminfo_out
        rocminfo_out=$(rocminfo 2>&1)
        if [[ "$rocminfo_out" == *"No AMD GPUs detected"* ]]; then
            test_results+="rocminfo: No AMD GPUs were detected."
        else
            local gpu_name
            gpu_name=$(echo "$rocminfo_out" | grep "Marketing Name:" | head -1 | sed 's/.*Marketing Name:\s*//')
            test_results+="✓ rocminfo check PASSED.\n  Detected GPU: ${gpu_name}"
        fi
    fi

    if ! command -v rocm-smi &> /dev/null; then
         test_results+="\n\nERROR: 'rocm-smi' command not found."
    else
        if rocm-smi -i &> /dev/null; then
            test_results+="\n✓ rocm-smi check PASSED."
        else
            test_results+="\n\nWARNING: 'rocm-smi' command failed to execute properly."
        fi
    fi

    whiptail --title "Installation Complete" --msgbox "ROCm ${rocm_version_to_install} installation is complete.\n\n${test_results}\n\nA system restart is highly recommended for all changes to take effect." 24 78
}

show_launch_menu() {
    local CHOICE
    CHOICE=$(whiptail --title "Launch Menu" --menu "Choose a tool to start" 20 78 12 \
        "comfyui" "Start ComfyUI" \
        "sdnext" "Start SD.Next" \
        "a1111" "Start Automatic1111" \
        "invokeai" "Start InvokeAI" \
        "fooocus" "Start Fooocus" \
        "forge" "Start SD WebUI Forge" \
        3>&1 1>&2 2>&3) || return 0

    case "$CHOICE" in
        comfyui) start_tool "ComfyUI" "./scripts/start/comfyui.sh" "$COMFYUI_DIR/main.py" ;;
        sdnext) start_tool "SD.Next" "./scripts/start/sdnext.sh" "$SDNEXT_DIR/webui.sh" ;;
        a1111) start_tool "Automatic1111" "./scripts/start/automatic1111.sh" "$AUTOMATIC1111_DIR/webui.sh" ;;
        invokeai) start_tool "InvokeAI" "./scripts/start/invokeai.sh" "$INVOKEAI_DIR/invoke.sh" ;;
        fooocus) start_tool "Fooocus" "./scripts/start/fooocus.sh" "$FOOOCUS_DIR/launch.py" ;;
        forge) start_tool "SD WebUI Forge" "./scripts/start/forge.sh" "$FORGE_DIR/webui.sh" ;;
    esac
}

show_install_menu() {
    local CHOICE
    CHOICE=$(whiptail --title "Install Menu" --menu "Choose what to install. Use UP/DOWN arrows, press Enter to select." 20 78 12 \
        "base" "Base Installation (ROCm & PyTorch)" \
        "" "" \
        "comfyui" "Install ComfyUI" \
        "sdnext" "Install SD.Next" \
        "a1111" "Install Automatic1111" \
        "invokeai" "Install InvokeAI" \
        "fooocus" "Install Fooocus" \
        "forge" "Install SD WebUI Forge" \
        3>&1 1>&2 2>&3) || return 0

    case "$CHOICE" in
        base) install_rocm_pytorch ;;
        comfyui) install_tool "ComfyUI" "./scripts/install/comfyui.sh" "$COMFYUI_DIR" ;;
        sdnext) install_tool "SD.Next" "./scripts/install/sdnext.sh" "$SDNEXT_DIR" ;;
        a1111) install_tool "Automatic1111" "./scripts/install/automatic1111.sh" "$AUTOMATIC1111_DIR" ;;
        invokeai) install_tool "InvokeAI" "./scripts/install/invokeai.sh" "$INVOKEAI_DIR" ;;
        fooocus) install_tool "Fooocus" "./scripts/install/fooocus.sh" "$FOOOCUS_DIR" ;;
        forge) install_tool "SD WebUI Forge" "./scripts/install/forge.sh" "$FORGE_DIR" ;;
    esac
}

show_remove_menu() {
    local CHOICE
    CHOICE=$(whiptail --title "Uninstall Menu" --menu "Choose a tool to remove" 20 78 12 \
        "comfyui" "Uninstall ComfyUI" \
        "sdnext" "Uninstall SD.Next" \
        "a1111" "Uninstall Automatic1111" \
        "invokeai" "Uninstall InvokeAI" \
        "fooocus" "Uninstall Fooocus" \
        "forge" "Uninstall SD WebUI Forge" \
        3>&1 1>&2 2>&3) || return 0

    case "$CHOICE" in
        comfyui) remove_tool_dir "$COMFYUI_DIR" "ComfyUI" ;;
        sdnext) remove_tool_dir "$SDNEXT_DIR" "SD.Next" ;;
        a1111) remove_tool_dir "$AUTOMATIC1111_DIR" "Automatic1111" ;;
        invokeai) remove_tool_dir "$INVOKEAI_DIR" "InvokeAI" ;;
        fooocus) remove_tool_dir "$FOOOCUS_DIR" "Fooocus" ;;
        forge) remove_tool_dir "$FORGE_DIR" "SD WebUI Forge" ;;
    esac
}

show_manage_menu() {
    local CHOICE
    CHOICE=$(whiptail --title "Manage Tools" --menu "Install or uninstall tools." 15 78 4 \
        "install" "Install a new tool" \
        "uninstall" "Uninstall an existing tool" \
        3>&1 1>&2 2>&3) || return 0

    case "$CHOICE" in
        install) show_install_menu ;;
        uninstall) show_remove_menu ;;
    esac
}

show_system_menu() {
    local CHOICE
    CHOICE=$(whiptail --title "System & Updates" --menu "Manage system components and updates." 15 78 4 \
        "update" "Update Everything (Script & AI Stack)" \
        "drivers" "Manage AMD GPU Drivers" \
        3>&1 1>&2 2>&3) || return 0

    case "$CHOICE" in
        update) run_full_update ;;
        drivers) manage_gpu_drivers ;;
    esac
}


# --- Main ---
ensure_scripts_executable

# Check if we need to run stack update after a self-update
if [ -f "$POST_UPDATE_FLAG" ]; then
    rm "$POST_UPDATE_FLAG"
    if (whiptail --title "Update Step 2: AI Stack" --yesno "The menu script has been updated.\n\nDo you want to proceed with updating the AI Stack (ROCm, PyTorch, Tools) now?" 12 78); then
        update_ai_stack
    fi
fi

while true; do
    CHOICE=$(whiptail --title "AI Tools Suite (Linux / WSL2, AMD ROCm)" --menu "Main Menu" 20 78 10 \
        "launch" "Launch an AI tool" \
        "manage" "Manage Tools (Install / Uninstall)" \
        "system" "System & Updates" \
        "status" "Check Installation Status" \
        3>&1 1>&2 2>&3) || { clear; exit 0; }

    case "$CHOICE" in
        launch) show_launch_menu ;;
        manage) show_manage_menu ;;
        system) show_system_menu ;;
        status) check_status ;;
    esac
done