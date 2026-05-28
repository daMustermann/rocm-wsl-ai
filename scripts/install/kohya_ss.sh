#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
[ -f "$SCRIPT_DIR/lib/common.sh" ] && source "$SCRIPT_DIR/lib/common.sh" || { echo "common.sh not found"; exit 1; }

# ==============================================================================
# kohya_ss Installation — LoRA, DreamBooth & Fine-Tuning Model Training
# Repository: https://github.com/bmaltais/kohya_ss
# Uses a dedicated virtual environment (kohya_env) to avoid dependency conflicts
# ==============================================================================

KOHYA_DIR="$HOME/kohya_ss"
KOHYA_VENV_NAME="kohya_env"
KOHYA_VENV="$HOME/$KOHYA_VENV_NAME"

standard_header "kohya_ss — LoRA & Model Training Installation"

require_wsl

# --- System Dependencies ---
log "Installing system dependencies..."
ensure_apt_packages \
    git python3-venv python3-pip python3-tk python3-dev \
    libgl1-mesa-glx libglib2.0-0 libsm6 libxrender1 libxext6 \
    build-essential

# --- Clone / Update Repository ---
git_clone_or_update "https://github.com/bmaltais/kohya_ss.git" "$KOHYA_DIR"

# --- Create Dedicated Virtual Environment ---
log "Creating dedicated virtual environment: $KOHYA_VENV_NAME"
python3 -m venv "$KOHYA_VENV"
# shellcheck disable=SC1090
source "$KOHYA_VENV/bin/activate"

pip install --upgrade pip setuptools wheel

# --- Install PyTorch with ROCm support ---
log "Installing PyTorch 2.9.1 with ROCm 7.2 support..."
pip install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/rocm7.2

# --- Install kohya_ss Requirements ---
cd "$KOHYA_DIR"

for req_file in requirements.txt requirements_linux.txt; do
    if [ -f "$req_file" ]; then
        log "Installing from $req_file..."
        pip install -r "$req_file" || warn "Some packages in $req_file could not be installed — continuing"
    fi
done

# Key training packages (best-effort, non-fatal)
pip install accelerate transformers diffusers safetensors || true
pip install lycoris_lora 2>/dev/null || true
pip install prodigyopt 2>/dev/null || true
pip install wandb 2>/dev/null || true

# --- Configure accelerate for single-GPU ROCm (non-interactive) ---
log "Configuring Hugging Face Accelerate for single-GPU ROCm..."
ACCEL_CONFIG_DIR="$HOME/.config/accelerate"
mkdir -p "$ACCEL_CONFIG_DIR"
cat > "$ACCEL_CONFIG_DIR/default_config.yaml" << 'ACCEL_EOF'
compute_environment: LOCAL_MACHINE
debug: false
distributed_type: 'NO'
downcast_bf16: 'no'
gpu_ids: all
machine_rank: 0
main_training_function: main
mixed_precision: fp16
num_machines: 1
num_processes: 1
rdzv_backend: static
same_network: true
tpu_env: []
tpu_use_cluster: false
tpu_use_sudo: false
use_cpu: false
ACCEL_EOF

deactivate

success "kohya_ss installed successfully!"
cat <<EOF

  Location  : $KOHYA_DIR
  Venv      : $KOHYA_VENV
  GUI port  : http://localhost:7861

Models / datasets go in: $KOHYA_DIR/models/ and your chosen data directories.
Launch via the menu: Launch Tool → kohya_ss

EOF
