#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../../lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/../../lib/common.sh"
else
    echo "common.sh not found" >&2; exit 1
fi

# ===============================================================================
# Update Script for ROCm AI Setup - 2026 Edition (ROCm 7.2.3 + ROCDXG)
# Updates ROCm, PyTorch, ComfyUI, SD.Next, Automatic1111, kohya_ss, Ollama
# Includes self-update for the toolkit itself (git pull)
# ===============================================================================

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
COMFYUI_DIR="$HOME/ComfyUI"
SDNEXT_DIR="$HOME/SD.Next"
AUTOMATIC1111_DIR="$HOME/stable-diffusion-webui"
TEXTGEN_DIR="$HOME/text-generation-webui"
KOHYA_DIR="$HOME/kohya_ss"
KOHYA_VENV="$HOME/kohya_env"
# Toolkit root (two levels up from scripts/utils/)
TOOLKIT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Map prior function names
print_header(){ headline "$@"; }
print_section(){ headline "$@"; }
print_success(){ success "$@"; }
print_warning(){ warn "$@"; }
print_error(){ err "$@"; }
print_info(){ log "$@"; }

check_venv() {
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        print_error "Python virtual environment not found at $VENV_PATH"
        print_error "Please run the ROCm/PyTorch setup script first (1_setup_pytorch_rocm_wsl.sh)"
        exit 1
    fi
    # shellcheck disable=SC1091
    source "$VENV_PATH/bin/activate"
    print_success "Virtual environment activated"
}

update_amdgpu_drivers() {
    print_section "Updating AMD GPU Drivers (reinstall)"
    print_warning "AMD GPU driver updates require removal and reinstallation"
    read -p "Continue with AMD GPU driver update? (y/N): " -n 1 -r; echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "AMD GPU driver update cancelled"; return 0; fi
    if [ ! -f "./9_install_amd_drivers.sh" ]; then
        print_error "AMD driver installation script not found (9_install_amd_drivers.sh)"; return 1; fi
    chmod +x ./9_install_amd_drivers.sh && ./9_install_amd_drivers.sh || return 1
    print_success "AMD GPU drivers updated. Restart terminal/WSL as needed."
}

update_rocm() {
    print_section "Updating ROCm stack"

    if ! is_wsl; then
        print_warning "ROCm stack update is optimized for WSL2."
    fi

    local UBUNTU_CODENAME
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || true)
    local AMDGPU_INSTALL_VERSION="7.2.3.70203-1"
    local AMDGPU_INSTALL_DEB="amdgpu-install_${AMDGPU_INSTALL_VERSION}_all.deb"

    local CURRENT_ROCM="unknown"
    if [ -f "/opt/rocm/.info/version" ]; then
        CURRENT_ROCM=$(head -1 /opt/rocm/.info/version 2>/dev/null | tr -cd '0-9.' | head -1)
    elif command -v rocminfo >/dev/null 2>&1; then
        CURRENT_ROCM="installed (version unknown)"
    fi
    print_info "Current ROCm version: ${CURRENT_ROCM}"

    if ! confirm "Continue with ROCm stack update via apt?"; then
        print_info "ROCm update cancelled"
        return 0
    fi

    ensure_apt_packages wget python3-setuptools python3-wheel || return 1

    if [[ "$UBUNTU_CODENAME" == "jammy" || "$UBUNTU_CODENAME" == "noble" ]]; then
        local AMDGPU_INSTALL_URL="https://repo.radeon.com/amdgpu-install/7.2.3/ubuntu/${UBUNTU_CODENAME}/${AMDGPU_INSTALL_DEB}"
        print_info "Refreshing AMD package source for ${UBUNTU_CODENAME}"
        if wget -q "$AMDGPU_INSTALL_URL" -O "/tmp/${AMDGPU_INSTALL_DEB}"; then
            sudo apt install -y "/tmp/${AMDGPU_INSTALL_DEB}" || return 1
            rm -f "/tmp/${AMDGPU_INSTALL_DEB}"
        else
            print_warning "Could not download ${AMDGPU_INSTALL_DEB}; continuing with current apt sources"
        fi
    else
        print_warning "Unsupported Ubuntu codename '${UBUNTU_CODENAME:-unknown}' for automatic amdgpu-install refresh"
        print_warning "Skipping amdgpu-install package refresh"
    fi

    sudo apt update -y
    sudo apt install -y rocm || {
        print_error "ROCm package update failed"
        return 1
    }

    sudo usermod -a -G render,video "$LOGNAME" 2>/dev/null || true

    local UPDATED_ROCM="unknown"
    if [ -f "/opt/rocm/.info/version" ]; then
        UPDATED_ROCM=$(head -1 /opt/rocm/.info/version 2>/dev/null | tr -cd '0-9.' | head -1)
    fi
    print_success "ROCm stack updated (detected: ${UPDATED_ROCM})"

    if [ ! -f "/opt/rocm/lib/librocdxg.so" ]; then
        print_warning "ROCDXG (librocdxg) not detected at /opt/rocm/lib/librocdxg.so"
        print_warning "If GPU compute fails in WSL, run scripts/install/upgrade_to_rocdxg.sh"
    fi

    print_info "WSL restart recommended after ROCm update: wsl --shutdown"
}

# Install a requirements.txt while deliberately skipping torch/torchvision/torchaudio.
# Without this guard, pip resolves torch from PyPI and downloads the CUDA build
# (1+ GB of nvidia_* packages) instead of keeping the installed ROCm wheels.
_pip_req() {
    local req_file="$1"
    [ -f "$req_file" ] || return 0
    # Strip torch, torchvision, torchaudio (and their extras) from the file before passing to pip
    grep -ivE '^[[:space:]]*(torch|torchvision|torchaudio)([>=<!;@# ]|$)' "$req_file" \
        | pip install --upgrade -r /dev/stdin || true
}

update_pytorch() {
    print_section "Updating PyTorch (ROCm 7.2.3) + Triton"
    check_venv
    python3 -c "import torch; print(f'PyTorch: {torch.__version__} (ROCm avail: {torch.cuda.is_available()})')" 2>/dev/null || true
    pip install --upgrade "torch==2.9.1" torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm7.2
    pip install -U --pre triton
    pip install -U sageattention
    print_success "PyTorch, Triton, and SageAttention updated"
}

update_comfyui() {
    print_section "Updating ComfyUI"
    local dir="$COMFYUI_DIR"; [ -d "$dir" ] || dir="$HOME/ComfyUI"
    [ -d "$dir" ] || { print_warning "ComfyUI not found"; return 1; }
    check_venv
    pushd "$dir" >/dev/null || return 1
    git pull || print_warning "Git pull failed"
    _pip_req requirements.txt
    # Update Manager and custom nodes
    for node_dir in custom_nodes/*/; do
        [ -d "$node_dir/.git" ] || continue
        pushd "$node_dir" >/dev/null; git pull || true
        _pip_req requirements.txt
        popd >/dev/null
    done
    popd >/dev/null
    print_success "ComfyUI updated"
}

update_sdnext() {
    print_section "Updating SD.Next"
    local dir="$SDNEXT_DIR"; [ -d "$dir" ] || dir="$HOME/SD.Next"
    [ -d "$dir" ] || { print_warning "SD.Next not found"; return 1; }
    pushd "$dir" >/dev/null || return 1
    git pull || print_warning "Git pull failed"
    if [ -f "launch.py" ]; then python launch.py --update || true; fi
    if [ -f "webui.py" ]; then python webui.py --update --exit || true; fi
    popd >/dev/null
    print_success "SD.Next updated"
}

update_automatic1111() {
    print_section "Updating Automatic1111"
    local dir="$AUTOMATIC1111_DIR"; [ -d "$dir" ] || dir="$HOME/stable-diffusion-webui"
    [ -d "$dir" ] || { print_warning "Automatic1111 not found"; return 1; }
    check_venv
    pushd "$dir" >/dev/null || return 1
    git pull || print_warning "Git pull failed"
    _pip_req requirements.txt
    # Update extensions
    for ext_dir in extensions/*/; do
        [ -d "$ext_dir/.git" ] || continue
        pushd "$ext_dir" >/dev/null; git pull || true; popd >/dev/null
    done
    popd >/dev/null
    print_success "Automatic1111 updated"
}

update_ollama() {
    print_section "Updating Ollama"
    if command -v ollama >/dev/null 2>&1; then
        curl -fsSL https://ollama.ai/install.sh | sh && print_success "Ollama updated" || print_warning "Ollama update failed"
        systemctl --user restart ollama.service 2>/dev/null || true
    else
        print_warning "Ollama not installed"
    fi
}

update_kohya_ss() {
    print_section "Updating kohya_ss"
    if [ ! -d "$KOHYA_DIR" ]; then
        print_warning "kohya_ss not installed at $KOHYA_DIR — skipping"
        return 1
    fi

    pushd "$KOHYA_DIR" >/dev/null || return 1
    git pull --rebase --autostash || print_warning "git pull had issues — continuing"

    if [ -f "$KOHYA_VENV/bin/activate" ]; then
        # shellcheck disable=SC1090
        source "$KOHYA_VENV/bin/activate"
        for req_file in requirements.txt requirements_linux.txt; do
            _pip_req "$req_file"
        done
        deactivate
    else
        print_warning "kohya_ss venv not found at $KOHYA_VENV"
    fi

    popd >/dev/null
    print_success "kohya_ss updated"
}

self_update_toolkit() {
    print_section "Toolkit Self-Update (git pull)"

    if [ ! -d "$TOOLKIT_DIR/.git" ]; then
        print_warning "$TOOLKIT_DIR is not a git repository."
        print_warning "Self-update is only available when the toolkit was installed via git clone."
        return 1
    fi

    print_info "Fetching updates from remote..."
    if ! git -C "$TOOLKIT_DIR" fetch origin 2>/dev/null; then
        print_warning "Could not reach remote. Check your internet connection."
        return 1
    fi

    local branch
    branch=$(git -C "$TOOLKIT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    local behind
    behind=$(git -C "$TOOLKIT_DIR" rev-list "HEAD..origin/$branch" --count 2>/dev/null || echo "0")

    if [ "$behind" = "0" ]; then
        print_success "Toolkit is already up to date — no new commits on origin/$branch."
        return 0
    fi

    print_info "$behind new commit(s) available on origin/$branch:"
    git -C "$TOOLKIT_DIR" log "HEAD..origin/$branch" --oneline --no-merges | head -20
    echo ""

    if confirm "Apply these updates now? (git pull --rebase)"; then
        if git -C "$TOOLKIT_DIR" pull --rebase --autostash; then
            print_success "Toolkit updated! Please restart menu.sh to apply changes."
        else
            print_warning "git pull failed. Try manually: git -C '$TOOLKIT_DIR' pull"
        fi
    else
        print_info "Update postponed."
    fi
}

    # Note: InvokeAI and Fooocus were removed from this toolkit to reduce
    # maintenance surface. If you need to re-add them, implement dedicated
    # installers and update handlers in the scripts/install and scripts/start
    # directories.

update_textgen() {
    print_section "Updating Text Generation WebUI"
    local dir="$TEXTGEN_DIR"; [ -d "$dir" ] || dir="$HOME/text-generation-webui"
    [ -d "$dir" ] || { print_warning "Text Generation WebUI not found"; return 1; }
    pushd "$dir" >/dev/null || return 1
    git pull || print_warning "Git pull failed"
    # Don't aggressively update optional extras to avoid breakage
    [ -f requirements.txt ] && print_info "Consider running: pip install -r requirements.txt --upgrade" || true
    popd >/dev/null
    print_success "Text Generation WebUI updated"
}

cleanup_cache() {
    print_section "Cleaning up cache and temporary files"
    check_venv
    pip cache purge || true
    sudo apt autoremove -y && sudo apt autoclean -y
    print_success "Cache cleanup completed"
}

verify_installations() {
    print_section "Verifying installations"
    check_venv
    print_info "ROCm verification:"
    if command -v rocminfo &> /dev/null; then
        rocminfo | grep -E 'Agent [0-9]+|Name:|Marketing Name:' | grep -A2 -B1 'Agent' | grep -v -E 'Host|CPU' | head -5
    else
        print_warning "rocminfo not available"
    fi
    print_info "PyTorch verification:"
    python3 - <<'PY'
import torch
print(f'PyTorch Version: {torch.__version__}')
print(f'ROCm Available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'GPU Count: {torch.cuda.device_count()}')
    print(f'GPU Name: {torch.cuda.get_device_name(0)}')
PY
    print_info "Triton verification:"
    python3 -c "import triton; print(f'Triton Version: {triton.__version__}')" || print_warning "Triton not available"
    print_success "Verification completed"
}

show_update_menu() {
    if command -v gum >/dev/null 2>&1; then
        _show_update_menu_gum
    else
        _show_update_menu_text
    fi
}

_show_update_menu_gum() {
    while true; do
        clear
        echo ""
        gum style --bold --foreground 212 --border normal --border-foreground 212 --padding "0 2" "🔄 Update Manager — ROCm AI Toolkit v3.4.0"
        echo ""
        local CHOICE
        CHOICE=$(gum choose --cursor="» " --header="Select what to update:" \
            "s.  🤖 Smart Update (auto-scan all, update what is outdated)" \
            "0.  🔄 Update Toolkit (self-update / git pull)" \
            "1.  ⚠️  Reinstall AMD GPU drivers" \
            "2.  ROCm stack" \
            "3.  PyTorch (ROCm 7.2) + Triton" \
            "4.  ComfyUI" \
            "5.  SD.Next" \
            "6.  Automatic1111" \
            "7.  kohya_ss" \
            "8.  Ollama" \
            "9.  Text Generation WebUI" \
            "10. 🚀 Update ALL AI tools (3-9, no drivers)" \
            "11. 🧹 Clean caches" \
            "12. ✅ Verify installations" \
            "q.  ← Back")
        case "$CHOICE" in
            s.*|S.*) "$TOOLKIT_DIR/scripts/utils/smart_update.sh" ;;
            0.*) self_update_toolkit ;;
            1.*) update_amdgpu_drivers ;;
            2.*) update_rocm ;;
            3.*) update_pytorch ;;
            4.*) update_comfyui ;;
            5.*) update_sdnext ;;
            6.*) update_automatic1111 ;;
            7.*) update_kohya_ss ;;
            8.*) update_ollama ;;
            9.*) update_textgen ;;
            10.*) "$TOOLKIT_DIR/scripts/utils/smart_update.sh" ;;
            11.*) cleanup_cache ;;
            12.*) verify_installations ;;
            q.*|Q.*) return ;;
        esac
        echo ""
        read -rp "  Press Enter to continue..."
    done
}

_show_update_menu_text() {
    while true; do
        clear
        echo -e "${CYAN}🔄 Update Manager — ROCm AI Toolkit${NC}\n"
        echo -e "s.  ${GREEN}🤖 Smart Update (auto-scan all, update what is outdated)${NC}"
        echo -e "0.  ${YELLOW}🔄 Update Toolkit (self-update / git pull)${NC}"
        echo -e "1.  ${YELLOW}Reinstall AMD GPU drivers${NC}"
        echo -e "2.  Update ROCm stack"
        echo -e "3.  Update PyTorch (ROCm) + Triton"
        echo -e "4.  Update ComfyUI"
        echo -e "5.  Update SD.Next"
        echo -e "6.  Update Automatic1111"
        echo -e "7.  Update kohya_ss"
        echo -e "8.  Update Ollama"
        echo -e "9.  Update Text Generation WebUI"
        echo ""
        echo -e "10. ${GREEN}Update ALL AI tools (3-9, no drivers)${NC}"
        echo -e "11. Clean caches"
        echo -e "12. Verify installations"
        echo -e "q.  Back"
        echo -e "${BLUE}========================================${NC}"
        read -rp "Choice: " choice
        case $choice in
            s|S) "$TOOLKIT_DIR/scripts/utils/smart_update.sh" ;;
            0) self_update_toolkit ;;
            1) update_amdgpu_drivers ;;
            2) update_rocm ;;
            3) update_pytorch ;;
            4) update_comfyui ;;
            5) update_sdnext ;;
            6) update_automatic1111 ;;
            7) update_kohya_ss ;;
            8) update_ollama ;;
            9) update_textgen ;;
            10) "$TOOLKIT_DIR/scripts/utils/smart_update.sh" ;;
            11) cleanup_cache ;;
            12) verify_installations ;;
            q|Q) return ;;
            *) print_error "Invalid option" ;;
        esac
        read -rp "Press Enter to continue..." _
    done
}

# --- Main ---
# Guard: only run the interactive menu when executed directly,
# not when sourced by smart_update.sh to borrow update functions.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${SMART_UPDATE_SOURCED:-0}" != "1" ]]; then
    if ! grep -q Microsoft /proc/version 2>/dev/null; then
        print_warning "This script is optimized for WSL2; native Linux may differ."
    fi
    show_update_menu
fi
