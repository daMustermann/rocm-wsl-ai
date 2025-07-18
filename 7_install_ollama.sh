#!/bin/bash

# ==============================================================================
# Script to install Ollama with ROCm support for running local AI models
# Compatible with Ubuntu 24.04 LTS and WSL2
# ==============================================================================

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

# --- Script Start ---
print_header "Installing Ollama with ROCm Support"

# Exit immediately if a command exits with a non-zero status
set -e

# --- 1. Check Prerequisites ---
print_info "Checking prerequisites..."

if [ ! -f "$VENV_PATH/bin/activate" ]; then
    print_warning "Python virtual environment not found at $VENV_PATH"
    print_info "Ollama can work independently, but having the ROCm environment is recommended"
fi

# Check for ROCm
if ! command -v rocminfo &> /dev/null; then
    print_warning "ROCm tools not found. Please install ROCm first for GPU acceleration"
    print_info "You can still install Ollama, but it will run on CPU only"
    read -p "Continue with installation? (y/N): " continue_install
    if [[ ! $continue_install =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# --- 2. Install Ollama ---
print_info "Installing Ollama..."

# Download and install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

print_success "Ollama installed"

# --- 3. Configure for ROCm ---
print_info "Configuring Ollama for ROCm support..."

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
Environment="HSA_OVERRIDE_GFX_VERSION=11.0.0"
Environment="HIP_VISIBLE_DEVICES=0"
Environment="ROCM_PATH=/opt/rocm"

[Install]
WantedBy=default.target
EOF

# Reload systemd and enable the service
systemctl --user daemon-reload
systemctl --user enable ollama.service

print_success "Ollama service configured"

# --- 4. Start Ollama Service ---
print_info "Starting Ollama service..."

systemctl --user start ollama.service

# Wait a moment for the service to start
sleep 3

# Check if service is running
if systemctl --user is-active --quiet ollama.service; then
    print_success "Ollama service is running"
else
    print_warning "Ollama service may not have started correctly"
    print_info "You can check status with: systemctl --user status ollama.service"
fi

# --- 5. Test Installation ---
print_info "Testing Ollama installation..."

# Give the service a moment to fully start
sleep 2

if ollama list &> /dev/null; then
    print_success "Ollama is responding correctly"
else
    print_warning "Ollama may not be responding yet. This is normal on first startup."
fi

# --- 6. Download Popular Models ---
print_info "Would you like to download some popular AI models?"
echo "Available models:"
echo "1. Llama 3.2 3B (Smaller, faster)"
echo "2. Llama 3.2 8B (Balanced)"
echo "3. Mistral 7B (Good performance)"
echo "4. CodeLlama 7B (Code-focused)"
echo "5. Skip model download"

read -p "Enter your choice (1-5): " model_choice

case $model_choice in
    1)
        print_info "Downloading Llama 3.2 3B..."
        ollama pull llama3.2:3b
        print_success "Llama 3.2 3B downloaded"
        ;;
    2)
        print_info "Downloading Llama 3.2 8B..."
        ollama pull llama3.2:8b
        print_success "Llama 3.2 8B downloaded"
        ;;
    3)
        print_info "Downloading Mistral 7B..."
        ollama pull mistral:7b
        print_success "Mistral 7B downloaded"
        ;;
    4)
        print_info "Downloading CodeLlama 7B..."
        ollama pull codellama:7b
        print_success "CodeLlama 7B downloaded"
        ;;
    5)
        print_info "Skipping model download"
        ;;
    *)
        print_warning "Invalid choice, skipping model download"
        ;;
esac

# --- 7. Create Helper Scripts ---
print_info "Creating helper scripts..."

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

print_success "Helper scripts created"

# --- 8. Install Open WebUI (Optional) ---
print_info "Would you like to install Open WebUI for a ChatGPT-like interface? (y/N)"
read -p "Install Open WebUI? " install_webui

if [[ $install_webui =~ ^[Yy]$ ]]; then
    print_info "Installing Open WebUI..."
    
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
    print_success "Open WebUI installed. Launch with: ~/start_openwebui.sh"
fi

print_header "Installation Complete!"

echo -e "${GREEN}Ollama has been installed successfully!${NC}"
echo ""
echo -e "${YELLOW}Quick Start:${NC}"
echo -e "• Start a chat: ${BLUE}~/start_ollama_chat.sh${NC}"
echo -e "• Manage models: ${BLUE}~/manage_ollama_models.sh${NC}"
echo -e "• Test API: ${BLUE}~/test_ollama_api.sh${NC}"
if [[ $install_webui =~ ^[Yy]$ ]]; then
echo -e "• Web interface: ${BLUE}~/start_openwebui.sh${NC}"
fi
echo ""
echo -e "${YELLOW}Service Commands:${NC}"
echo -e "• Start service: ${BLUE}systemctl --user start ollama.service${NC}"
echo -e "• Stop service: ${BLUE}systemctl --user stop ollama.service${NC}"
echo -e "• Service status: ${BLUE}systemctl --user status ollama.service${NC}"
echo ""
echo -e "${YELLOW}Direct Commands:${NC}"
echo -e "• List models: ${BLUE}ollama list${NC}"
echo -e "• Download model: ${BLUE}ollama pull <model-name>${NC}"
echo -e "• Chat with model: ${BLUE}ollama run <model-name>${NC}"
echo ""
echo -e "${YELLOW}ROCm GPU Support:${NC}"
if command -v rocminfo &> /dev/null; then
    echo -e "• ROCm detected - GPU acceleration should be available"
    echo -e "• Check GPU usage with: ${BLUE}rocm-smi${NC}"
else
    echo -e "• ROCm not detected - running on CPU only"
    echo -e "• Install ROCm first for GPU acceleration"
fi
echo ""
print_success "Installation completed successfully!"
