#!/bin/bash

# ==============================================================================
# Install Text Generation WebUI for local LLMs (pairs well with ROCm via PyTorch)
# Uses existing genai_env venv when available
# ==============================================================================

VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
TEXTGEN_DIR="$HOME/text-generation-webui"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}$1${NC}"; }
success() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
err() { echo -e "${RED}$1${NC}"; }

set -e

log "Installing Text Generation WebUI..."

if [ -f "$VENV_PATH/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "$VENV_PATH/bin/activate"
else
  warn "Virtualenv nicht gefunden. Installation läuft systemweit/Python-User."
fi

# System deps (minimal)
sudo apt update
sudo apt install -y git python3-venv python3-pip

if [ ! -d "$TEXTGEN_DIR" ]; then
  git clone https://github.com/oobabooga/text-generation-webui.git "$TEXTGEN_DIR"
else
  warn "Text Generation WebUI Verzeichnis existiert bereits. Aktualisiere..."
  git -C "$TEXTGEN_DIR" pull || warn "Git pull fehlgeschlagen"
fi

cd "$TEXTGEN_DIR"

# Basic requirements; optional extras are heavy and model-dependent
if [ -f requirements.txt ]; then
  pip install -r requirements.txt
fi

# Create launch helper
cat > "$TEXTGEN_DIR/launch_textgen_rocm.sh" << 'EOF'
#!/bin/bash
# Use venv if present
if [ -f ~/genai_env/bin/activate ]; then
  source ~/genai_env/bin/activate
fi
cd ~/text-generation-webui
# --xformers often helps, but may be unavailable for ROCm; omit by default
python server.py --listen --api --chat "$@"
EOF
chmod +x "$TEXTGEN_DIR/launch_textgen_rocm.sh"

success "Text Generation WebUI installiert. Start: $TEXTGEN_DIR/launch_textgen_rocm.sh"
