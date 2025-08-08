#!/bin/bash
set -e
VENV=~/genai_env
DIR=~/stable-diffusion-webui-forge
echo "Installing SD WebUI Forge..."
[ -f "$VENV/bin/activate" ] && source "$VENV/bin/activate" || true
if [ ! -d "$DIR" ]; then
  git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git "$DIR" || git clone https://github.com/lllyasviel/stable-diffusion-webui-forge "$DIR"
fi
cd "$DIR"
chmod +x webui.sh || true
echo "Forge installed at $DIR"
