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
# Update Script for ROCm AI Setup - 2025 Edition (Fixed & Enhanced)
# Updates ROCm, PyTorch, ComfyUI, SD.Next, Automatic1111, Ollama
# Includes Text Generation WebUI update helper
# Note: Support for several legacy third-party tools has been removed to focus
# on maintaining a smaller, well-tested set of ROCm-compatible installers.
# ===============================================================================

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
COMFYUI_DIR="$HOME/ComfyUI"
SDNEXT_DIR="$HOME/SD.Next"
AUTOMATIC1111_DIR="$HOME/stable-diffusion-webui"
TEXTGEN_DIR="$HOME/text-generation-webui"

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

update_pytorch() {
    print_section "Updating PyTorch Nightly (ROCm) + Triton"
    check_venv
    print_info "Current PyTorch version:"
    python3 -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'ROCm available: {torch.cuda.is_available()}')" 2>/dev/null || true

    # Detect installed ROCm series (e.g., 6.5)
    local ROCM_VERSION_FILE="/opt/rocm/.info/version"
    local ROCM_SERIES="6.4"
    if [ -f "$ROCM_VERSION_FILE" ]; then
        local ROCM_FULL
        ROCM_FULL=$(cat "$ROCM_VERSION_FILE" 2>/dev/null | head -1 | tr -cd '0-9\n.' | head -1)
        local ROCM_MAJOR; ROCM_MAJOR=$(echo "$ROCM_FULL" | cut -d'.' -f1)
        local ROCM_MINOR; ROCM_MINOR=$(echo "$ROCM_FULL" | cut -d'.' -f2)
        if [ -n "$ROCM_MAJOR" ] && [ -n "$ROCM_MINOR" ]; then
            ROCM_SERIES="${ROCM_MAJOR}.${ROCM_MINOR}"
        fi
    fi
    print_info "Using ROCm series: ${ROCM_SERIES}"

    local INDEX_URL="https://download.pytorch.org/whl/nightly/rocm${ROCM_SERIES}"
    print_info "PyTorch Nightly index: ${INDEX_URL}"

    pip install --upgrade pip wheel
    pip install --pre torch torchvision torchaudio --index-url "${INDEX_URL}"
    pip install -U --pre triton || print_warning "Triton nightly not available"
    print_success "PyTorch Nightly and Triton updated"
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

update_pytorch() {
    print_section "Updating PyTorch (ROCm) + Triton"
    check_venv
    python3 -c "import torch; print(f'PyTorch: {torch.__version__} (ROCm avail: {torch.cuda.is_available()})')" 2>/dev/null || true
    pip install --upgrade "torch==2.8.0" torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.4
    pip install -U --pre triton
    print_success "PyTorch and Triton updated"
}

update_comfyui() {
    print_section "Updating ComfyUI"
    local dir="$COMFYUI_DIR"; [ -d "$dir" ] || dir="$HOME/ComfyUI"
    [ -d "$dir" ] || { print_warning "ComfyUI not found"; return 1; }
    check_venv
    pushd "$dir" >/dev/null || return 1
    git pull || print_warning "Git pull failed"
    [ -f requirements.txt ] && pip install -r requirements.txt --upgrade || true
    # Update Manager and custom nodes
    for node_dir in custom_nodes/*/; do
        [ -d "$node_dir/.git" ] || continue
        pushd "$node_dir" >/dev/null; git pull || true
        [ -f requirements.txt ] && pip install -r requirements.txt --upgrade || true
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
    [ -f requirements.txt ] && pip install -r requirements.txt --upgrade || true
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
    while true; do
        clear
        print_header "AI Tools Update Menu - 2025"
    echo -e "${CYAN}🔄 Select what to update:${NC}\n"
    echo -e "1.  ${YELLOW}Reinstall AMD GPU drivers${NC}"
    echo -e "2.  Update ROCm stack"
    echo -e "3.  Update PyTorch (ROCm) + Triton"
    echo -e "4.  Update ComfyUI"
    echo -e "5.  Update SD.Next"
    echo -e "6.  Update Automatic1111"
    echo -e "7.  Update Ollama"
    # Legacy support entries removed where applicable.
    echo -e "10. Update Text Generation WebUI"
    echo ""
    echo -e "11. ${GREEN}Update ALL AI tools (excluding drivers)${NC}"
    echo -e "12. Clean caches"
    echo -e "13. Verify installation"
    echo -e "0.  Back"
        echo -e "${BLUE}========================================${NC}"
    read -p "Choice: " choice
        case $choice in
            1) update_amdgpu_drivers ;;
            2) update_rocm ;;
            3) update_pytorch ;;
            4) update_comfyui ;;
            5) update_sdnext ;;
            6) update_automatic1111 ;;
            7) update_ollama ;;
            # removed
            10) update_textgen ;;
            11)
                print_header "Updating all AI tools"
                update_pytorch; update_comfyui; update_sdnext; update_automatic1111; update_ollama; update_textgen
                cleanup_cache; verify_installations
                print_success "All AI tools updated"
                ;;
            12) cleanup_cache ;;
            13) verify_installations ;;
            0) return ;;
            *) print_error "Invalid option" ;;
        esac
        read -p "Press Enter to continue..." _
    done
}

# --- Main ---
echo "Starting AI Tools Update Script..."
if ! grep -q Microsoft /proc/version; then
    print_warning "This script is optimized for WSL2; native Linux may differ."
fi
show_update_menu
