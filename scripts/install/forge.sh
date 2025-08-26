#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh" || { echo "common.sh missing" >&2; exit 1; }

VENV="genai_env"
DIR="$HOME/stable-diffusion-webui-forge"

standard_header "Installing SD WebUI Forge"

if [ -f "$HOME/$VENV/bin/activate" ]; then
  ensure_venv "$VENV" || warn "Could not activate venv"
else
  warn "Venv '$VENV' not found (continuing)"
fi

git_clone_or_update https://github.com/lllyasviel/stable-diffusion-webui-forge.git "$DIR" || err "Git clone/update failed"

if [ -f "$DIR/webui.sh" ]; then chmod +x "$DIR/webui.sh" || true; fi

success "Forge installed at $DIR"
echo "Run: (cd $DIR && ./webui.sh --listen)"
