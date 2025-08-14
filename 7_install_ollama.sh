#!/bin/bash
set -euo pipefail

# Install Ollama with (optional) ROCm support

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$script_dir/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$script_dir/common.sh"
else
    echo "common.sh not found. Aborting." >&2; exit 1
fi

VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"

standard_header "Installing Ollama (Local LLM Inference)"

# --- 1. Check Prerequisites ---
log "Checking prerequisites..."

if [ ! -f "$VENV_PATH/bin/activate" ]; then
    warn "Python virtual environment not found at $VENV_PATH (optional)."
    log "Ollama can run standalone; GPU acceleration depends on ROCm + driver + model backend."
fi

if ! has_rocm; then
    warn "ROCm not detected. Ollama will run CPU-only for most models."
    confirm "Continue without ROCm?" || { err "Aborted by user"; exit 1; }
fi

# --- 2. Install Ollama ---
log "Installing Ollama..."

# Download and install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

success "Ollama installed"

# --- 3. Configure for ROCm ---
log "Configuring systemd user service..."

# Create systemd user service directory if it doesn't exist
mkdir -p ~/.config/systemd/user

# Create Ollama service configuration with ROCm support
cat > ~/.config/systemd/user/ollama.service << 'EOF'
[Unit]
Description=Ollama Server
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=%i
Group=%i
Restart=always
RestartSec=3
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_ORIGINS=*"
EnvironmentFile=-%h/.config/rocm-wsl-ai/gpu.env
Environment="HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION:-11.0.0}"
Environment="HIP_VISIBLE_DEVICES=0"
Environment="ROCM_PATH=/opt/rocm"

[Install]
WantedBy=default.target
EOF

# Reload systemd and enable the service
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user daemon-reload
    systemctl --user enable ollama.service || warn "Could not enable ollama.service"
    success "Ollama service configured"
else
    warn "systemd user instance not available. You must start 'ollama serve' manually."
fi

# --- 4. Start Ollama Service ---
if command -v systemctl >/dev/null 2>&1 && systemctl --user start ollama.service 2>/dev/null; then
    log "Starting Ollama service..."
    sleep 3
    if systemctl --user is-active --quiet ollama.service; then
        success "Ollama service is running"
    else
        warn "Ollama service may not have started correctly (check: systemctl --user status ollama.service)"
    fi
else
    warn "Skipping service start (systemd user not available). Run: ollama serve"
fi

# --- 5. Test Installation ---
log "Testing Ollama binary..."

# Give the service a moment to fully start
sleep 2

if command -v ollama >/dev/null 2>&1 && ollama list &>/dev/null; then
    success "Ollama responded"
else
    warn "Ollama not responding yet (may still be starting)."
fi

# --- 6. Download Popular Models ---
log "Optional: download a starter model"
echo "Available models:"
echo "1. Llama 3.2 3B (Smaller, faster)"
echo "2. Llama 3.2 8B (Balanced)"
echo "3. Mistral 7B (Good performance)"
echo "4. CodeLlama 7B (Code-focused)"
echo "5. Skip model download"

read -p "Enter your choice (1-5): " model_choice

case $model_choice in
    1)
    log "Downloading Llama 3.2 3B..."
        ollama pull llama3.2:3b
    success "Llama 3.2 3B downloaded"
        ;;
    2)
    log "Downloading Llama 3.2 8B..."
        ollama pull llama3.2:8b
    success "Llama 3.2 8B downloaded"
        ;;
    3)
    log "Downloading Mistral 7B..."
        ollama pull mistral:7b
    success "Mistral 7B downloaded"
        ;;
    4)
    log "Downloading CodeLlama 7B..."
        ollama pull codellama:7b
    success "CodeLlama 7B downloaded"
        ;;
    5)
    log "Skipping model download"
        ;;
    *)
    warn "Invalid choice, skipping model download"
        ;;
esac

# --- 7. Create Helper Scripts ---
log "Creating helper scripts..."

# Create a chat script
cat > ~/start_ollama_chat.sh << 'EOF'
#!/bin/bash

echo "🤖 Ollama Chat Interface"
echo "======================="

# Check if Ollama service is running
if ! systemctl --user is-active --quiet ollama.service; then
    echo "Starting Ollama service..."
    systemctl --user start ollama.service
    sleep 3
fi

# List available models
echo "Available models:"
ollama list

echo ""
read -p "Enter model name to chat with (or press Enter for default): " model_name

if [ -z "$model_name" ]; then
    # Try to find a default model
    if ollama list | grep -q "llama3.2:3b"; then
        model_name="llama3.2:3b"
    elif ollama list | grep -q "llama3.2:8b"; then
        model_name="llama3.2:8b"
    elif ollama list | grep -q "mistral:7b"; then
        model_name="mistral:7b"
    else
        echo "No default model found. Please specify a model name."
        exit 1
    fi
fi

echo "Starting chat with $model_name..."
echo "Type 'exit' or press Ctrl+C to quit."
echo ""

ollama run $model_name
EOF

chmod +x ~/start_ollama_chat.sh

# Create an API test script
cat > ~/test_ollama_api.sh << 'EOF'
#!/bin/bash

echo "🧪 Testing Ollama API"
echo "===================="

# Check if Ollama service is running
if ! systemctl --user is-active --quiet ollama.service; then
    echo "Starting Ollama service..."
    systemctl --user start ollama.service
    sleep 3
fi

echo "Testing API endpoint..."
curl -s http://localhost:11434/api/tags | python3 -m json.tool 2>/dev/null || echo "API test failed or no models installed"

echo ""
echo "Service status:"
systemctl --user status ollama.service --no-pager -l
EOF

chmod +x ~/test_ollama_api.sh

# Create model management script
cat > ~/manage_ollama_models.sh << 'EOF'
#!/bin/bash

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🤖 Ollama Model Manager${NC}"
echo "======================"

while true; do
    echo ""
    echo "1. List installed models"
    echo "2. Download a new model"
    echo "3. Remove a model"
    echo "4. Popular models to try"
    echo "5. Check disk usage"
    echo "0. Exit"
    echo ""
    read -p "Enter your choice: " choice

    case $choice in
        1)
            echo -e "${GREEN}Installed models:${NC}"
            ollama list
            ;;
        2)
            read -p "Enter model name to download (e.g., llama3.2:3b): " model_name
            if [ ! -z "$model_name" ]; then
                ollama pull "$model_name"
            fi
            ;;
        3)
            echo -e "${YELLOW}Installed models:${NC}"
            ollama list
            read -p "Enter model name to remove: " model_name
            if [ ! -z "$model_name" ]; then
                ollama rm "$model_name"
            fi
            ;;
        4)
            echo -e "${GREEN}Popular models to try:${NC}"
            echo "• llama3.2:3b - Fast, 2GB"
            echo "• llama3.2:8b - Balanced, 4.7GB"
            echo "• mistral:7b - Good performance, 4.1GB"
            echo "• codellama:7b - Code-focused, 3.8GB"
            echo "• phi:latest - Compact, 1.6GB"
            echo "• gemma:7b - Google's model, 5.0GB"
            echo "• neural-chat:7b - Conversation-focused, 4.1GB"
            ;;
        5)
            echo -e "${GREEN}Ollama disk usage:${NC}"
            du -h ~/.ollama 2>/dev/null || echo "No models installed yet"
            ;;
        0)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid option!"
            ;;
    esac
done
EOF

chmod +x ~/manage_ollama_models.sh

success "Helper scripts created"

# --- 8. Install Open WebUI (Optional) ---
log "Optional: Install Open WebUI (ChatGPT-like UI)"
read -p "Install Open WebUI? " install_webui

if [[ $install_webui =~ ^[Yy]$ ]]; then
    log "Installing Open WebUI..."
    
    # Activate virtual environment if available
    if [ -f "$VENV_PATH/bin/activate" ]; then
        source "$VENV_PATH/bin/activate"
    fi
    
    pip install open-webui
    
    # Create launch script for Open WebUI
    cat > ~/start_openwebui.sh << 'EOF'
#!/bin/bash

# Activate virtual environment if available
if [ -f ~/genai_env/bin/activate ]; then
    source ~/genai_env/bin/activate
fi

# Check if Ollama is running
if ! systemctl --user is-active --quiet ollama.service; then
    echo "Starting Ollama service..."
    systemctl --user start ollama.service
    sleep 3
fi

echo "Starting Open WebUI..."
echo "Access the interface at: http://localhost:8080"
echo "Use Ctrl+C to stop"

open-webui serve --host 0.0.0.0 --port 8080
EOF
    
    chmod +x ~/start_openwebui.sh
    success "Open WebUI installed. Launch with: ~/start_openwebui.sh"
fi

headline "Installation Complete"

echo -e "${GREEN}Ollama has been installed successfully${NC}"
echo ""
echo -e "${YELLOW}Quick Start:${NC}"
echo -e "• Start a chat: ${BLUE}~/start_ollama_chat.sh${NC}"
echo -e "• Manage models: ${BLUE}~/manage_ollama_models.sh${NC}"
echo -e "• Test API: ${BLUE}~/test_ollama_api.sh${NC}"
if [[ $install_webui =~ ^[Yy]$ ]]; then
echo -e "• Web interface: ${BLUE}~/start_openwebui.sh${NC}"
fi
echo ""
if command -v systemctl >/dev/null 2>&1; then
    echo -e "${YELLOW}Service Commands:${NC}"
    echo -e "• Start service: ${BLUE}systemctl --user start ollama.service${NC}"
    echo -e "• Stop service: ${BLUE}systemctl --user stop ollama.service${NC}"
    echo -e "• Service status: ${BLUE}systemctl --user status ollama.service${NC}"
    echo ""
fi
echo ""
echo -e "${YELLOW}Direct Commands:${NC}"
echo -e "• List models: ${BLUE}ollama list${NC}"
echo -e "• Download model: ${BLUE}ollama pull <model-name>${NC}"
echo -e "• Chat with model: ${BLUE}ollama run <model-name>${NC}"
echo ""
echo -e "${YELLOW}ROCm GPU Support:${NC}"
if has_rocm; then
    echo -e "• ROCm detected - GPU acceleration should be available"
    echo -e "• Check GPU usage with: ${BLUE}rocm-smi${NC}"
else
    echo -e "• ROCm not detected - running on CPU only"
    echo -e "• Install ROCm first for GPU acceleration"
fi
echo ""
success "Installation completed successfully"
