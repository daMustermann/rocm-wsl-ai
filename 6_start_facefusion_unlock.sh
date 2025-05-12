#!/bin/bash

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
FACEFUSION_UNLOCK_DIR="$HOME/facefusion-unlock"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Starting facefusion-unlock ===${NC}"

# Check if facefusion-unlock is installed
if [ ! -f "$FACEFUSION_UNLOCK_DIR/run.py" ]; then
    echo -e "${RED}[ERROR] facefusion-unlock (run.py) not found in '$FACEFUSION_UNLOCK_DIR'.${NC}"
    echo -e "${YELLOW}Please install facefusion-unlock first (Option in the main menu).${NC}"
    exit 1
fi

# Check if ROCm/PyTorch environment exists
if [ ! -f "$VENV_PATH/bin/activate" ]; then
    echo -e "${RED}[ERROR] Python virtual environment '$VENV_NAME' not found at '$VENV_PATH'.${NC}"
    echo -e "${YELLOW}Please install ROCm and PyTorch first (Option 1 in the main menu).${NC}"
    exit 1
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

echo -e "${YELLOW}[INFO] Launching facefusion-unlock...${NC}"
echo -e "${YELLOW}This might take a moment to start. Check your browser at http://127.0.0.1:7860 (default) or the address shown in the terminal.${NC}"

# Run facefusion-unlock
# Add any necessary arguments here. For ROCm, it usually auto-detects if onnxruntime-rocm is installed.
# Common arguments might include --listen, --port, etc.
python run.py

# Deactivate virtual environment (might not be reached if run.py runs indefinitely)
deactivate

echo -e "${GREEN}[INFO] facefusion-unlock script finished or was closed.${NC}"
read -p "Press Enter to return to the menu..."
