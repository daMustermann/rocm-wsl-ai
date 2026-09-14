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
    print_section "Updating the ROCm stack"

    # The version to install is discovered from AMD's repositories rather than
    # hardcoded. This block previously pinned ROCm 7.2.3 and the matching
    # amdgpu-install build number, so it silently stopped doing anything useful
    # as soon as AMD published a newer release.
    # shellcheck disable=SC1091
    if [ -f "$TOOLKIT_DIR/lib/version.sh" ]; then
        . "$TOOLKIT_DIR/lib/version.sh"
    fi

    local codename current target
    codename="$(va_ubuntu_codename 2>/dev/null || lsb_release -cs 2>/dev/null || echo unknown)"
    current="$(va_rocm_installed 2>/dev/null || echo 'not installed')"

    print_info "Current ROCm version: ${current}"
    print_info "Querying AMD's repositories for the newest release ..."

    target="$(va_latest_rocm "$codename" 2>/dev/null || echo '')"
    if [ -z "$target" ]; then
        print_error "Could not determine the newest ROCm release (offline?)"
        print_info "The full upgrade handles this better: ./upgrade.sh"
        return 1
    fi

    if [ "$current" != "not installed" ] && ! va_lt "$current" "$target"; then
        print_success "ROCm ${current} is already the newest release for ${codename}."
        print_info "For a complete stack check (PyTorch, ROCDXG, settings), run: ./upgrade.sh"
        return 0
    fi

    print_info "ROCm ${current} -> ${target} is available."
    print_info ""
    print_info "A ROCm upgrade also requires rebuilding PyTorch against it, so this"
    print_info "is best done by the toolkit's automatic upgrade, which handles the"
    print_info "whole sequence and migrates your settings."
    print_info ""

    if confirm "Run the full automatic upgrade now?"; then
        if [ -f "$TOOLKIT_DIR/upgrade.sh" ]; then
            bash "$TOOLKIT_DIR/upgrade.sh"
            return $?
        fi
        print_error "upgrade.sh not found in $TOOLKIT_DIR"
        return 1
    fi

    print_info "Cancelled. Nothing was changed."
    return 0
}

# Install a requirements.txt while deliberately skipping torch/torchvision/torchaudio.
# Without this guard, pip resolves torch from PyPI and downloads the CUDA build
# (1+ GB of nvidia_* packages) instead of keeping the installed ROCm wheels.
_pip_req() {
    local req_file="$1"
    pip_install_filtered_requirements "$req_file" || true

    if [ -d "./sd-scripts" ] && [ -f "./sd-scripts/setup.py" ]; then
        pip install -e "./sd-scripts" || true
    fi
}

update_pytorch() {
    print_section "Updating PyTorch and Triton (AMD ROCm build)"

    # This function used to pin torch==2.9.1 from download.pytorch.org and then
    # run `pip install -U --pre triton`. Both were wrong:
    #   * Pinning downgraded a user who had already upgraded, and the index URL
    #     does not track AMD's ROCm releases.
    #   * `--pre triton` installs a *prerelease from PyPI*, which has no ROCm
    #     support and overwrites the AMD triton build that torch was compiled
    #     against. That breaks attention kernels in a way that is very hard to
    #     diagnose.
    # The correct behaviour is to install the newest AMD wheels that match the
    # installed ROCm release.
    # shellcheck disable=SC1091
    if [ -f "$TOOLKIT_DIR/lib/version.sh" ]; then
        . "$TOOLKIT_DIR/lib/version.sh"
    fi

    check_venv

    python3 -c "import torch; print('Currently: PyTorch', torch.__version__, '(ROCm available:', torch.cuda.is_available(), ')')" 2>/dev/null || true

    local installed_rocm pytag target
    installed_rocm="$(va_rocm_installed 2>/dev/null || echo '')"
    pytag="$(va_python_tag "$(command -v python3)")"

    if [ -z "$installed_rocm" ]; then
        print_error "Could not determine the installed ROCm version."
        print_info "Run the full upgrade instead:  ./upgrade.sh"
        return 1
    fi

    # Prefer the ROCm release already installed, so PyTorch matches the driver
    # stack rather than dragging the whole system forward.
    target="$installed_rocm"
    if ! va_resolve_torch_wheels "$target" "$pytag" >/dev/null 2>&1; then
        print_warning "No AMD wheels found for ROCm ${target} and Python ${pytag}."
        target="$(va_best_installable_rocm "$pytag")"
        print_info "Falling back to ROCm ${target}."
    fi

    local wheels
    if ! wheels="$(va_resolve_torch_wheels "$target" "$pytag")"; then
        print_error "Could not resolve AMD PyTorch wheels. Check your connection."
        print_info "The full upgrade handles this more thoroughly:  ./upgrade.sh"
        return 1
    fi

    local ROCM_REL TORCH_VERSION TORCH_WHEEL TORCHVISION_WHEEL TORCHAUDIO_WHEEL TRITON_WHEEL
    eval "$wheels"
    print_info "Installing PyTorch ${TORCH_VERSION} + triton ${TRITON_WHEEL#triton-} (ROCm ${ROCM_REL})"

    local base="https://repo.radeon.com/rocm/manylinux/rocm-rel-${ROCM_REL}"
    local tmp
    tmp="$(mktemp -d /tmp/rocm-upd.XXXXXX)"
    local w ok=1
    for w in "$TORCH_WHEEL" "$TORCHVISION_WHEEL" "$TORCHAUDIO_WHEEL" "$TRITON_WHEEL"; do
        if ! wget -q "${base}/${w//+/%2B}" -O "$tmp/$w"; then
            print_error "Download failed: $w"
            ok=0
            break
        fi
    done

    if [ "$ok" = "1" ]; then
        pip install --no-cache-dir --force-reinstall --no-deps \
            "$tmp/$TORCH_WHEEL" "$tmp/$TORCHVISION_WHEEL" \
            "$tmp/$TORCHAUDIO_WHEEL" "$tmp/$TRITON_WHEEL" \
            && print_success "PyTorch, Triton and SageAttention updated" \
            || { print_error "PyTorch installation failed"; ok=0; }
    fi
    rm -rf "$tmp"
    [ "$ok" = "1" ] || return 1

    # Re-apply the WSL HSA runtime fix: a fresh torch wheel can restore the
    # bundled runtime that conflicts with ROCDXG.
    local loc torch_lib
    loc="$(pip show torch 2>/dev/null | awk -F ': ' '/^Location/{print $2}')"
    torch_lib="$loc/torch/lib"
    [ -n "$loc" ] && [ -d "$torch_lib" ] && rm -f "$torch_lib"/libhsa-runtime64.so* 2>/dev/null

    # Optional, and never fatal.
    pip install --no-cache-dir sageattention >/dev/null 2>&1 \
        && print_info "SageAttention refreshed" \
        || print_warning "SageAttention not installed (optional)"

    rm -f "${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}/.preflight" 2>/dev/null
    return 0
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
    git submodule sync --recursive || true
    git submodule update --init --recursive || print_warning "Failed to update kohya_ss submodules"

    if [ -f "$KOHYA_VENV/bin/activate" ]; then
        # shellcheck disable=SC1090
        source "$KOHYA_VENV/bin/activate"
        for req_file in requirements.txt requirements_linux.txt; do
            pip_install_filtered_requirements "$req_file" || print_warning "Some packages in $req_file could not be installed — continuing"
        done

        if [ -d "./sd-scripts" ] && [ -f "./sd-scripts/setup.py" ]; then
            pip install -e "./sd-scripts" || print_warning "Failed to install local sd-scripts package during update"
        fi

        pip install "gradio>=5.34.1" || print_warning "Failed to install gradio during update"
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
        gum style --bold --foreground 212 --border normal --border-foreground 212 --padding "0 2" "Update Manager - ROCm AI Toolkit"
        echo ""
        # Uses the toolkit's choose(), not `gum choose`: the result is captured
        # with $(...), so stdout is a pipe and gum's TUI cannot render into it.
        # gum then produces no output and never reads input, hanging forever.
        local CHOICE
        CHOICE="$(choose "Select what to update:" \
            "s|Smart Update (auto-scan all, update what is outdated)" \
            "0|Update Toolkit (self-update / git pull)" \
            "1|Reinstall AMD GPU drivers" \
            "2|ROCm stack" \
            "3|PyTorch (ROCm) + Triton" \
            "4|ComfyUI" \
            "5|SD.Next" \
            "6|Automatic1111" \
            "7|kohya_ss" \
            "8|Ollama" \
            "9|Text Generation WebUI" \
            "10|Update ALL AI tools" \
            "11|Clean caches" \
            "12|Verify installations" \
            "q|Back")" || return
        case "${CHOICE%%|*}" in
            s) "$TOOLKIT_DIR/scripts/utils/smart_update.sh" ;;
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
            q) return ;;
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
