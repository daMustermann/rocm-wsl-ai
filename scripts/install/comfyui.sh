#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$0")"
COMMON="$SCRIPT_DIR/common.sh"
[ -f "$COMMON" ] && source "$COMMON" || { echo "common.sh not found"; exit 1; }

VENV_NAME="genai_env"
COMFYUI_DIR="$HOME/ComfyUI"
COMFYUI_MANAGER_DIR="$COMFYUI_DIR/custom_nodes/comfyui-manager"
COMFYUI_LORA_DIR="$COMFYUI_DIR/custom_nodes/ComfyUI-Lora-Manager"

standard_header "ComfyUI Installation"
ensure_venv "$VENV_NAME" || { err "Run 1_setup_pytorch_rocm_wsl.sh first"; exit 1; }

git_clone_or_update https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"

if [ -f "$COMFYUI_DIR/requirements.txt" ]; then
    pip_install_if_exists "$COMFYUI_DIR/requirements.txt"
else
    err "requirements.txt missing in $COMFYUI_DIR"; exit 1
fi

mkdir -p "$COMFYUI_DIR/custom_nodes"
git_clone_or_update https://github.com/Comfy-Org/ComfyUI-Manager.git "$COMFYUI_MANAGER_DIR"
[ -f "$COMFYUI_MANAGER_DIR/requirements.txt" ] && pip_install_if_exists "$COMFYUI_MANAGER_DIR/requirements.txt"

# Also install LoRA Manager (willmiao/ComfyUI-Lora-Manager) to provide an integrated LoRA model manager
git_clone_or_update https://github.com/willmiao/ComfyUI-Lora-Manager.git "$COMFYUI_LORA_DIR" || true
[ -f "$COMFYUI_LORA_DIR/requirements.txt" ] && pip_install_if_exists "$COMFYUI_LORA_DIR/requirements.txt"

success "ComfyUI + Manager installed/updated"
cat <<EOF

Run:
    source ~/${VENV_NAME}/bin/activate
    cd ${COMFYUI_DIR}
    python main.py --listen 0.0.0.0 --port 8188

Models go in: ${COMFYUI_DIR}/models/
EOF

exit 0
