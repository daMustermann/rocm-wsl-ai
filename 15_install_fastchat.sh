#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh" || { echo "common.sh missing" >&2; exit 1; }

VENV="genai_env"
DIR="$HOME/FastChat"

standard_header "Installing FastChat"

if [ -f "$HOME/$VENV/bin/activate" ]; then
  ensure_venv "$VENV" || warn "Could not activate venv"
else
  warn "Venv '$VENV' not found (continuing)"
fi

log "Installing Python package (fschat)"
pip install --upgrade pip wheel
pip install fschat || pip install fastchat || err "FastChat package install failed"

git_clone_or_update https://github.com/lm-sys/FastChat.git "$DIR" || err "Git clone/update failed"

success "FastChat installed"
echo "Run: (cd $DIR && python3 -m fastchat.serve.controller)"
