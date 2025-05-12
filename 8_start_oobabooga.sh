#!/bin/bash

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
OOBABOOGA_DIR="$HOME/text-generation-webui"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Starting Oobabooga (text-generation-webui) ===${NC}"

# Check if Oobabooga is installed
if [ ! -f "$OOBABOOGA_DIR/server.py" ]; then
    echo -e "${RED}[ERROR] Oobabooga (server.py) not found in '$OOBABOOGA_DIR'.${NC}"
    echo -e "${YELLOW}Please install Oobabooga first (Option in the main menu).${NC}"
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
cd "$OOBABOOGA_DIR"
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Failed to navigate to $OOBABOOGA_DIR.${NC}"
    deactivate
    exit 1
fi

echo -e "${YELLOW}[INFO] Launching Oobabooga (text-generation-webui)...${NC}"
echo -e "${YELLOW}This might take a moment to start. Check your browser at http://127.0.0.1:7860 (default) or the address shown in the terminal.${NC}"
echo -e "${YELLOW}For AMD GPUs (ROCm), common startup flags are --listen --chat --model-menu --api --rocm --no-cache${NC}"
echo -e "${YELLOW}Adjust these flags as needed based on your preferences and system capabilities.${NC}"

# Run Oobabooga
# The --rocm flag is important for AMD GPUs.
# Other flags like --listen (to make it accessible over network), --chat, --model-menu are common.
# The exact flags might depend on the version and specific needs.
# The user might need to adjust these.
# Using a common set of flags for ROCm:
python server.py --listen --chat --model-menu --api --rocm --no-cache

# Deactivate virtual environment (might not be reached if server.py runs indefinitely)
deactivate

echo -e "${GREEN}[INFO] Oobabooga (text-generation-webui) script finished or was closed.${NC}"
read -p "Press Enter to return to the menu..."
