#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh" || { echo "common.sh not found" >&2; exit 1; }

VENV_NAME="genai_env"
TEXTGEN_DIR="$HOME/text-generation-webui"

standard_header "Installing Text Generation WebUI"
if [ -f "$HOME/$VENV_NAME/bin/activate" ]; then
  ensure_venv "$VENV_NAME" || warn "Could not activate venv"
else
  warn "Venv '$VENV_NAME' not found; continuing with system Python"
fi

ensure_apt_packages git python3-venv python3-pip
git_clone_or_update https://github.com/oobabooga/text-generation-webui.git "$TEXTGEN_DIR" || err "Git clone/update failed"
cd "$TEXTGEN_DIR"

if [ -f requirements.txt ]; then
  pip_install_if_exists requirements.txt
else
  warn "requirements.txt not found"
fi

cat > "$TEXTGEN_DIR/launch_textgen_rocm.sh" << 'EOF'
#!/bin/bash
if [ -f ~/genai_env/bin/activate ]; then
  source ~/genai_env/bin/activate
fi
cd ~/text-generation-webui
python server.py --listen --api --chat "$@"
EOF
chmod +x "$TEXTGEN_DIR/launch_textgen_rocm.sh" || warn "chmod failed"

success "Text Generation WebUI installed"
echo "Launch: $TEXTGEN_DIR/launch_textgen_rocm.sh"
