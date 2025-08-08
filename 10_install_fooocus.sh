#!/bin/bash

# ==============================================================================
# Install Fooocus (Image Generation) with ROCm-friendly environment
# Works within the existing genai_env venv
# ==============================================================================

VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
FOOOCUS_DIR="$HOME/Fooocus"

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

log "Installing Fooocus..."

if [ ! -f "$VENV_PATH/bin/activate" ]; then
  err "Virtualenv nicht gefunden: $VENV_PATH"
  exit 1
fi

# shellcheck disable=SC1091
source "$VENV_PATH/bin/activate"

# Clone repo
if [ ! -d "$FOOOCUS_DIR" ]; then
  git clone https://github.com/lllyasviel/Fooocus.git "$FOOOCUS_DIR"
else
  warn "Fooocus Verzeichnis existiert bereits. Aktualisiere..."
  git -C "$FOOOCUS_DIR" pull || warn "Git pull fehlgeschlagen"
fi

cd "$FOOOCUS_DIR"

# Install deps conservatively
if [ -f requirements_versions.txt ]; then
  pip install -r requirements_versions.txt
elif [ -f requirements.txt ]; then
  pip install -r requirements.txt
fi

# Create a simple launch helper
cat > "$FOOOCUS_DIR/launch_fooocus_rocm.sh" << 'EOF'
#!/bin/bash
source ~/genai_env/bin/activate
cd ~/Fooocus
# Typical launch; add --listen for remote access
python launch.py --listen 0.0.0.0 --port 7865 "$@"
EOF
chmod +x "$FOOOCUS_DIR/launch_fooocus_rocm.sh"

success "Fooocus installiert. Start: $FOOOCUS_DIR/launch_fooocus_rocm.sh"
