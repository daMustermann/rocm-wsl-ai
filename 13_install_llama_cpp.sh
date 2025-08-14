#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh" || { echo "common.sh missing" >&2; exit 1; }

DIR="$HOME/llama.cpp"

standard_header "Installing llama.cpp"

ensure_apt_packages build-essential cmake git

git_clone_or_update https://github.com/ggerganov/llama.cpp.git "$DIR" || err "Git clone/update failed"

cd "$DIR"
log "Building (CPU by default) ..."
make -j"$(nproc)" || { err "Build failed"; exit 1; }

success "llama.cpp installed at $DIR"
echo "Next: place GGUF models in $DIR/models and run ./server --host 0.0.0.0"
