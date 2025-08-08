#!/bin/bash
set -e
DIR=~/KoboldCpp
echo "Installing KoboldCpp..."
sudo apt update && sudo apt install -y git build-essential cmake
if [ ! -d "$DIR" ]; then
  git clone https://github.com/LostRuins/koboldcpp.git "$DIR"
else
  git -C "$DIR" pull || true
fi
cd "$DIR"
./build.sh || echo "Build script may prompt later."
echo "KoboldCpp installed at $DIR"
