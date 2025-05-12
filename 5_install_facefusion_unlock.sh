#!/bin/bash

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
FACEFUSION_UNLOCK_DIR="$HOME/facefusion-unlock"
FACEFUSION_UNLOCK_REPO="https://github.com/hassan-sd/facefusion-unlock.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Installing facefusion-unlock ===${NC}"

# Check if ROCm/PyTorch environment exists
if [ ! -f "$VENV_PATH/bin/activate" ]; then
    echo -e "${RED}[ERROR] Python virtual environment '$VENV_NAME' not found at '$VENV_PATH'.${NC}"
    echo -e "${YELLOW}Please install ROCm and PyTorch first (Option 1 in the main menu).${NC}"
    exit 1
fi

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}[ERROR] git is not installed. Please install git first.${NC}"
    echo -e "${YELLOW}You can typically install it with: sudo apt update && sudo apt install git -y${NC}"
    exit 1
fi

# Clone the repository if it doesn't exist
if [ ! -d "$FACEFUSION_UNLOCK_DIR" ]; then
    echo -e "${YELLOW}[INFO] Cloning facefusion-unlock repository...${NC}"
    git clone "$FACEFUSION_UNLOCK_REPO" "$FACEFUSION_UNLOCK_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] Failed to clone facefusion-unlock repository.${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}[INFO] facefusion-unlock directory already exists. Skipping clone.${NC}"
    echo -e "${YELLOW}If you want to update, please remove the directory '$FACEFUSION_UNLOCK_DIR' and run this script again, or update manually via git pull.${NC}"
fi

# Activate virtual environment
echo -e "${YELLOW}[INFO] Activating Python virtual environment...${NC}"
source "$VENV_PATH/bin/activate"

# Navigate to the directory
cd "$FACEFUSION_UNLOCK_DIR"
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to navigate to $FACEFUSION_UNLOCK_DIR.${NC}"
    deactivate
    exit 1
fi

# Install dependencies
echo -e "${YELLOW}[INFO] Installing dependencies for facefusion-unlock...${NC}"
echo -e "${YELLOW}This might take a while.${NC}"

# Check for requirements.txt
if [ ! -f "requirements.txt" ]; then
    echo -e "${RED}[ERROR] requirements.txt not found in $FACEFUSION_UNLOCK_DIR.${NC}"
    echo -e "${YELLOW}The repository structure might have changed. Please check the facefusion-unlock GitHub page for installation instructions.${NC}"
    deactivate
    exit 1
fi

# Ensure onnxruntime-rocm is used if available, or onnxruntime if not.
# The requirements.txt might already specify this, but we can try to be explicit.
# For ROCm, onnxruntime-rocm is preferred.
# We assume PyTorch with ROCm is already installed in the venv.

# Check if onnxruntime-rocm is already in requirements or install it specifically for ROCm
if grep -q "onnxruntime-rocm" requirements.txt; then
    echo -e "${YELLOW}[INFO] onnxruntime-rocm found in requirements.txt. Proceeding with standard installation.${NC}"
    pip install -r requirements.txt
else
    echo -e "${YELLOW}[INFO] onnxruntime-rocm not explicitly found in requirements.txt.${NC}"
    echo -e "${YELLOW}[INFO] Attempting to install onnxruntime-rocm for AMD GPU support, then other requirements.${NC}"
    # Try to install onnxruntime-rocm first. If it fails, it might not be available for the current Python/ROCm version.
    # The version should be compatible with the installed PyTorch.
    # This is a best-effort attempt; specific versioning might be needed.
    pip install onnxruntime-rocm
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}[WARNING] Failed to install onnxruntime-rocm. This might be okay if onnxruntime (CPU/generic) is sufficient or already part of requirements.${NC}"
        echo -e "${YELLOW}[INFO] Proceeding to install other requirements from requirements.txt.${NC}"
        pip install -r requirements.txt
    else
        echo -e "${GREEN}[SUCCESS] onnxruntime-rocm installed.${NC}"
        echo -e "${YELLOW}[INFO] Installing other requirements (excluding onnxruntime if it was listed separately).${NC}"
        # Install other requirements, potentially skipping onnxruntime if it was listed and we installed onnxruntime-rocm
        pip install -r <(grep -v "onnxruntime" requirements.txt)
    fi
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to install dependencies for facefusion-unlock.${NC}"
    deactivate
    exit 1
fi

# Deactivate virtual environment
deactivate

echo -e "${GREEN}[SUCCESS] facefusion-unlock installation script finished.${NC}"
echo -e "${YELLOW}Please check for any errors above.${NC}"
echo -e "${YELLOW}You can now try to start facefusion-unlock using the main menu.${NC}"
