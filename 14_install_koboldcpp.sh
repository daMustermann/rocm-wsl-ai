#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh" || { echo "common.sh missing" >&2; exit 1; }

DIR="$HOME/KoboldCpp"

standard_header "Installing KoboldCpp"

ensure_apt_packages git build-essential cmake
git_clone_or_update https://github.com/LostRuins/koboldcpp.git "$DIR" || err "Git clone/update failed"
cd "$DIR"
if [ -x ./build.sh ]; then
  log "Running build script..."
  ./build.sh || warn "Build script did not complete fully"
else
  warn "build.sh not executable"
fi

success "KoboldCpp installed at $DIR"
echo "Run: (cd $DIR && ./koboldcpp --help)"
