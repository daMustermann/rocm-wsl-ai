#!/bin/bash
set -e
VENV=~/genai_env
DIR=~/FastChat
echo "Installing FastChat..."
[ -f "$VENV/bin/activate" ] && source "$VENV/bin/activate" || true
pip install --upgrade pip wheel
pip install fschat || pip install fastchat
if [ ! -d "$DIR" ]; then
  git clone https://github.com/lm-sys/FastChat.git "$DIR"
else
  git -C "$DIR" pull || true
fi
echo "FastChat installed. Use provided scripts to start servers."
