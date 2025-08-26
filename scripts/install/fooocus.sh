#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh" || { echo "common.sh not found" >&2; exit 1; }

VENV_NAME="genai_env"
FOOOCUS_DIR="$HOME/Fooocus"

standard_header "Installing Fooocus"
ensure_venv "$VENV_NAME" || { err "Run 1_setup_pytorch_rocm_wsl.sh first"; exit 1; }

git_clone_or_update https://github.com/lllyasviel/Fooocus.git "$FOOOCUS_DIR" || err "Git clone/update failed"
cd "$FOOOCUS_DIR"

if [ -f requirements_versions.txt ]; then
  log "Installing requirements_versions.txt"
  pip install -r requirements_versions.txt
elif [ -f requirements.txt ]; then
  pip_install_if_exists requirements.txt
else
  warn "No requirements file found"
fi

cat > "$FOOOCUS_DIR/launch_fooocus_rocm.sh" << 'EOF'
#!/bin/bash
source ~/genai_env/bin/activate
cd ~/Fooocus
python launch.py --listen 0.0.0.0 --port 7865 "$@"
EOF
chmod +x "$FOOOCUS_DIR/launch_fooocus_rocm.sh" || warn "chmod failed"

success "Fooocus installed"
echo "Launch: $FOOOCUS_DIR/launch_fooocus_rocm.sh"
