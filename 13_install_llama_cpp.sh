#!/bin/bash
set -e
DIR=~/llama.cpp
echo "Installing llama.cpp (build with CPU; ROCm build optional)..."
sudo apt update && sudo apt install -y build-essential cmake git
if [ ! -d "$DIR" ]; then
  git clone https://github.com/ggerganov/llama.cpp.git "$DIR"
else
  git -C "$DIR" pull || true
fi
cd "$DIR"
make -j$(nproc)
echo "llama.cpp installed at $DIR. Run ./server after placing GGUF models."
