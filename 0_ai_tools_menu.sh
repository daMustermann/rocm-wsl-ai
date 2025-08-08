#!/bin/bash

# ==============================================================================
# AI Tools Suite for AMD GPUs on WSL2 - 2025 (TUI with whiptail)
# - Always latest ROCm & PyTorch Nightly
# - Image Gen: ComfyUI, SD.Next, Automatic1111, InvokeAI, Fooocus, SD WebUI Forge
# - LLMs: Ollama, Text Generation WebUI, llama.cpp, KoboldCpp, FastChat
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
TEXTGEN_DIR="$HOME/text-generation-webui"
REPO_REMOTE="origin"
FORGE_DIR="$HOME/stable-diffusion-webui-forge"
LLAMACPP_DIR="$HOME/llama.cpp"
KOBOLDCPP_DIR="$HOME/KoboldCpp"
FASTCHAT_DIR="$HOME/FastChat"

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

# --- Self-Update (GitHub) ---
self_update_repo() {
    print_header "Projekt Selbst-Update (GitHub)"
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        print_info "Aktueller Branch: ${CURRENT_BRANCH}"
        print_info "Hole Updates vom Remote..."
        git fetch --all --prune || { print_error "git fetch fehlgeschlagen"; return 1; }

        # Bestmöglicher Upstream ermitteln
        if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
            UPSTREAM="@{u}"
        else
            # Fallback auf origin/main
            UPSTREAM="${REPO_REMOTE}/main"
            print_warning "Kein Upstream gesetzt. Vergleiche gegen ${UPSTREAM}"
        fi

        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse "$UPSTREAM" 2>/dev/null || echo "")
        BASE=$(git merge-base @ "$UPSTREAM" 2>/dev/null || echo "")

        if [ -z "$REMOTE" ] || [ -z "$BASE" ]; then
            print_warning "Upstream konnte nicht ermittelt werden."
            read -p "Trotzdem 'git pull' ausführen? (y/N): " -n 1 -r; echo
            [[ $REPLY =~ ^[Yy]$ ]] || return 0
            git pull --rebase || git pull || { print_error "git pull fehlgeschlagen"; return 1; }
            print_success "Repository aktualisiert"
            return 0
        fi

        if [ "$LOCAL" = "$REMOTE" ]; then
            print_success "Bereits auf dem neuesten Stand"
        elif [ "$LOCAL" = "$BASE" ]; then
            print_info "Es sind Updates verfügbar. Ziehe Änderungen..."
            git pull --rebase || git pull || { print_error "git pull fehlgeschlagen"; return 1; }
            print_success "Repository aktualisiert"
        elif [ "$REMOTE" = "$BASE" ]; then
            print_warning "Lokale Commits sind voraus. Kein automatisches Pull."
            print_info "Bitte manuell mergen/rebasen."
        else
            print_warning "Lokale und Remote-Verläufe weichen ab."
            print_info "Bitte manuell Konflikte lösen."
        fi
    else
        print_warning "Kein Git-Repository erkannt."
        print_info "Du kannst das Repo klonen: https://github.com/daMustermann/rocm-wsl-ai"
    fi
    read -p "Press Enter to continue..."
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

install_fooocus() {
    print_header "Installing Fooocus"
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        print_error "Python virtual environment not found! Erst ROCm/PyTorch installieren (Installation → Option)"
        return 1
    fi
    if [ -f "./10_install_fooocus.sh" ]; then
        chmod +x ./10_install_fooocus.sh && ./10_install_fooocus.sh
        print_success "Fooocus installiert"
    else
        print_error "10_install_fooocus.sh nicht gefunden"
    fi
    read -p "Press Enter to continue..."
}

start_fooocus() {
    print_header "Starting Fooocus"
    if [ ! -d "$FOOOCUS_DIR" ]; then
        print_error "Fooocus nicht installiert"
        return 1
    fi
    source "$VENV_PATH/bin/activate"
    cd "$FOOOCUS_DIR"
    python launch.py --listen 0.0.0.0 --port 7865
    read -p "Press Enter to continue..."
}

install_textgen() {
    print_header "Installing Text Generation WebUI"
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        print_error "Python virtual environment not found! Erst ROCm/PyTorch installieren"
        return 1
    fi
    if [ -f "./11_install_textgen_webui.sh" ]; then
        chmod +x ./11_install_textgen_webui.sh && ./11_install_textgen_webui.sh
        print_success "Text Generation WebUI installiert"
    else
        print_error "11_install_textgen_webui.sh nicht gefunden"
    fi
    read -p "Press Enter to continue..."
}

start_textgen() {
    print_header "Starting Text Generation WebUI"
    if [ ! -d "$TEXTGEN_DIR" ]; then
        print_error "Text Generation WebUI nicht installiert"
        return 1
    fi
    source "$VENV_PATH/bin/activate"
    cd "$TEXTGEN_DIR"
    python server.py --listen --api --chat
    read -p "Press Enter to continue..."
}

# --- Additional Tools (stubs for installers/starters/removers) ---
install_forge() { print_header "Installing SD WebUI Forge"; if [ -f "./12_install_forge.sh" ]; then chmod +x ./12_install_forge.sh && ./12_install_forge.sh; else print_error "12_install_forge.sh not found"; fi; read -p "Press Enter to continue..."; }
start_forge() { [ -d "$FORGE_DIR" ] && cd "$FORGE_DIR" && ./webui.sh --use-rocm || print_error "Forge not installed"; read -p "Press Enter to continue..."; }

install_llamacpp() { print_header "Installing llama.cpp"; if [ -f "./13_install_llama_cpp.sh" ]; then chmod +x ./13_install_llama_cpp.sh && ./13_install_llama_cpp.sh; else print_error "13_install_llama_cpp.sh not found"; fi; read -p "Press Enter to continue..."; }
start_llamacpp() { [ -d "$LLAMACPP_DIR" ] && cd "$LLAMACPP_DIR" && ./server -c 2048 || print_error "llama.cpp not installed"; read -p "Press Enter to continue..."; }

install_koboldcpp() { print_header "Installing KoboldCpp"; if [ -f "./14_install_koboldcpp.sh" ]; then chmod +x ./14_install_koboldcpp.sh && ./14_install_koboldcpp.sh; else print_error "14_install_koboldcpp.sh not found"; fi; read -p "Press Enter to continue..."; }
start_koboldcpp() { [ -d "$KOBOLDCPP_DIR" ] && cd "$KOBOLDCPP_DIR" && ./koboldcpp.sh || print_error "KoboldCpp not installed"; read -p "Press Enter to continue..."; }

install_fastchat() { print_header "Installing FastChat"; if [ -f "./15_install_fastchat.sh" ]; then chmod +x ./15_install_fastchat.sh && ./15_install_fastchat.sh; else print_error "15_install_fastchat.sh not found"; fi; read -p "Press Enter to continue..."; }
start_fastchat() { [ -d "$FASTCHAT_DIR" ] && cd "$FASTCHAT_DIR" && ./start_server.sh || print_error "FastChat not installed"; read -p "Press Enter to continue..."; }

# --- Removal routines ---
remove_tool_dir() {
    local dir="$1"; local name="$2"
    if [ -d "$dir" ]; then
        print_warning "Removing $name at $dir"
        read -p "Confirm removal? This deletes the folder. (y/N): " -n 1 -r; echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$dir" && print_success "$name removed" || print_error "Failed to remove $name"
        fi
    else
        print_warning "$name not found"
    fi
}

remove_menu() {
    local CHOICE
    CHOICE=$(whiptail --title "Remove Tools" --menu "Select a tool to remove" 20 70 12 \
        "comfyui" "ComfyUI" \
        "sdnext" "SD.Next" \
        "a1111" "Automatic1111" \
        "invokeai" "InvokeAI" \
        "fooocus" "Fooocus" \
        "textgen" "Text Generation WebUI" \
        "forge" "SD WebUI Forge" \
        "llamacpp" "llama.cpp" \
        "koboldcpp" "KoboldCpp" \
        "fastchat" "FastChat" \
        3>&1 1>&2 2>&3) || return 0
    case "$CHOICE" in
        comfyui) remove_tool_dir "$COMFYUI_DIR" "ComfyUI" ;;
        sdnext) remove_tool_dir "$SDNEXT_DIR" "SD.Next" ;;
        a1111) remove_tool_dir "$AUTOMATIC1111_DIR" "Automatic1111" ;;
        invokeai) remove_tool_dir "$INVOKEAI_DIR" "InvokeAI" ;;
        fooocus) remove_tool_dir "$FOOOCUS_DIR" "Fooocus" ;;
        textgen) remove_tool_dir "$TEXTGEN_DIR" "Text Generation WebUI" ;;
        forge) remove_tool_dir "$FORGE_DIR" "SD WebUI Forge" ;;
        llamacpp) remove_tool_dir "$LLAMACPP_DIR" "llama.cpp" ;;
        koboldcpp) remove_tool_dir "$KOBOLDCPP_DIR" "KoboldCpp" ;;
        fastchat) remove_tool_dir "$FASTCHAT_DIR" "FastChat" ;;
    esac
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

    # Check Fooocus
    if [ -d "$FOOOCUS_DIR" ] && [ -f "$FOOOCUS_DIR/launch.py" ]; then
        print_success "✓ Fooocus installed"
    else
        print_error "✗ Fooocus not installed"
    fi

    # Check Text Generation WebUI
    if [ -d "$TEXTGEN_DIR" ] && [ -f "$TEXTGEN_DIR/server.py" ]; then
        print_success "✓ Text Generation WebUI installed"
    else
        print_error "✗ Text Generation WebUI not installed"
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
        local CHOICE
        CHOICE=$(whiptail --title "Installation" --menu "Choose what to install" 20 80 12 \
            "sys" "AMD GPU Drivers / ROCm" \
            "base" "ROCm & PyTorch Nightly (base)" \
            "img_comfy" "ComfyUI" \
            "img_sdnext" "SD.Next" \
            "img_a1111" "Automatic1111" \
            "img_invokeai" "InvokeAI" \
            "img_fooocus" "Fooocus" \
            "img_forge" "SD WebUI Forge" \
            "llm_ollama" "Ollama" \
            "llm_textgen" "Text Generation WebUI" \
            "llm_llamacpp" "llama.cpp" \
            "llm_koboldcpp" "KoboldCpp" \
            3>&1 1>&2 2>&3) || return 0
        case "$CHOICE" in
            sys) if [ -f "./9_install_amd_drivers.sh" ]; then chmod +x ./9_install_amd_drivers.sh && ./9_install_amd_drivers.sh; else whiptail --msgbox "9_install_amd_drivers.sh missing" 8 60; fi ;;
            base) install_rocm_pytorch ;;
            img_comfy) [ -d "$COMFYUI_DIR" ] && whiptail --msgbox "ComfyUI already installed" 8 50 || install_comfyui ;;
            img_sdnext) [ -d "$SDNEXT_DIR" ] && whiptail --msgbox "SD.Next already installed" 8 50 || install_sdnext ;;
            img_a1111) [ -d "$AUTOMATIC1111_DIR" ] && whiptail --msgbox "A1111 already installed" 8 50 || install_automatic1111 ;;
            img_invokeai) [ -d "$INVOKEAI_DIR" ] && whiptail --msgbox "InvokeAI already installed" 8 50 || install_invokeai ;;
            img_fooocus) [ -d "$FOOOCUS_DIR" ] && whiptail --msgbox "Fooocus already installed" 8 50 || install_fooocus ;;
            img_forge) [ -d "$FORGE_DIR" ] && whiptail --msgbox "Forge already installed" 8 50 || install_forge ;;
            llm_ollama) command -v ollama >/dev/null 2>&1 && whiptail --msgbox "Ollama already installed" 8 50 || install_ollama ;;
            llm_textgen) [ -d "$TEXTGEN_DIR" ] && whiptail --msgbox "TextGen WebUI already installed" 8 50 || install_textgen ;;
            llm_llamacpp) [ -d "$LLAMACPP_DIR" ] && whiptail --msgbox "llama.cpp already installed" 8 50 || install_llamacpp ;;
            llm_koboldcpp) [ -d "$KOBOLDCPP_DIR" ] && whiptail --msgbox "KoboldCpp already installed" 8 50 || install_koboldcpp ;;
        esac
    done
}

show_startup_menu() {
    while true; do
        local CHOICE
        CHOICE=$(whiptail --title "Launch" --menu "Start installed tools" 22 80 14 \
            "comfyui" "Start ComfyUI" \
            "sdnext" "Start SD.Next" \
            "a1111" "Start Automatic1111" \
            "invokeai" "Start InvokeAI" \
            "fooocus" "Start Fooocus" \
            "forge" "Start SD WebUI Forge" \
            "ollama" "Start Ollama Chat" \
            "ollama_mgmt" "Manage Ollama Models" \
            "textgen" "Start Text Generation WebUI" \
            "llamacpp" "Start llama.cpp server" \
            "koboldcpp" "Start KoboldCpp" \
            "fastchat" "Start FastChat" \
            "status" "Check Status" \
            3>&1 1>&2 2>&3) || return 0
        case "$CHOICE" in
            comfyui) [ -f "$COMFYUI_DIR/main.py" ] && start_comfyui || whiptail --msgbox "ComfyUI not installed" 8 40 ;;
            sdnext) [ -d "$SDNEXT_DIR" ] && start_sdnext || whiptail --msgbox "SD.Next not installed" 8 40 ;;
            a1111) [ -d "$AUTOMATIC1111_DIR" ] && start_automatic1111 || whiptail --msgbox "A1111 not installed" 8 40 ;;
            invokeai) [ -f "$INVOKEAI_DIR/launch_webui.sh" ] && start_invokeai || whiptail --msgbox "InvokeAI not installed" 8 40 ;;
            fooocus) [ -d "$FOOOCUS_DIR" ] && start_fooocus || whiptail --msgbox "Fooocus not installed" 8 40 ;;
            forge) [ -d "$FORGE_DIR" ] && start_forge || whiptail --msgbox "Forge not installed" 8 40 ;;
            ollama) command -v ollama >/dev/null 2>&1 && ~/start_ollama_chat.sh || whiptail --msgbox "Ollama not installed" 8 40 ;;
            ollama_mgmt) manage_ollama ;;
            textgen) [ -d "$TEXTGEN_DIR" ] && start_textgen || whiptail --msgbox "TextGen WebUI not installed" 8 50 ;;
            llamacpp) [ -d "$LLAMACPP_DIR" ] && start_llamacpp || whiptail --msgbox "llama.cpp not installed" 8 50 ;;
            koboldcpp) [ -d "$KOBOLDCPP_DIR" ] && start_koboldcpp || whiptail --msgbox "KoboldCpp not installed" 8 50 ;;
            fastchat) [ -d "$FASTCHAT_DIR" ] && start_fastchat || whiptail --msgbox "FastChat not installed" 8 50 ;;
            status) check_status ;;
        esac
    done
}

# --- Main Menu ---

while true; do
    CHOICE=$(whiptail --title "AI Tools Suite (WSL2, AMD ROCm)" --menu "Select an action" 20 80 10 \
        "install" "Install tools (categorized)" \
        "launch" "Launch installed tools" \
        "update" "Updates (drivers, ROCm, PyTorch Nightly, tools)" \
        "status" "Check installation status" \
        "selfupdate" "Self-update (GitHub)" \
        "remove" "Uninstall tools" \
        "drivers" "AMD driver management" \
        3>&1 1>&2 2>&3) || { clear; exit 0; }
    case "$CHOICE" in
        install) show_installation_menu ;;
        launch) show_startup_menu ;;
        update) update_system ;;
        status) check_status ;;
        selfupdate) self_update_repo ;;
        remove) remove_menu ;;
        drivers)
            if [ -f "./9_install_amd_drivers.sh" ]; then chmod +x ./9_install_amd_drivers.sh && ./9_install_amd_drivers.sh; else whiptail --msgbox "9_install_amd_drivers.sh missing" 8 50; fi ;;
    esac
done