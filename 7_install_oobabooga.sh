#!/bin/bash

# --- Configuration ---
VENV_NAME="genai_env"
VENV_PATH="$HOME/$VENV_NAME"
OOBABOOGA_DIR="$HOME/text-generation-webui"
OOBABOOGA_REPO="https://github.com/oobabooga/text-generation-webui.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Installing Oobabooga (text-generation-webui) ===${NC}"

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
if [ ! -d "$OOBABOOGA_DIR" ]; then
    echo -e "${YELLOW}[INFO] Cloning text-generation-webui repository...${NC}"
    git clone "$OOBABOOGA_REPO" "$OOBABOOGA_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] Failed to clone text-generation-webui repository.${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}[INFO] text-generation-webui directory already exists. Skipping clone.${NC}"
    echo -e "${YELLOW}If you want to update, please remove the directory '$OOBABOOGA_DIR' and run this script again, or update manually via git pull.${NC}"
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

echo -e "${YELLOW}[INFO] Installing dependencies for text-generation-webui...${NC}"
echo -e "${YELLOW}This might take a significant amount of time and download many packages.${NC}"

# Install requirements.
# text-generation-webui often uses specific PyTorch versions.
# We assume the existing genai_env has a compatible PyTorch for ROCm.
# It's crucial that the PyTorch version matches what text-generation-webui expects for ROCm.
# The 1_setup_pytorch_rocm_wsl.sh script should have installed a recent ROCm-enabled PyTorch.

# Check for requirements.txt or specific setup scripts
if [ -f "requirements.txt" ]; then
    echo -e "${YELLOW}[INFO] Found requirements.txt. Installing packages...${NC}"
    # Some users report issues with bitsandbytes on ROCm.
    # We might need to install a specific version or build from source if issues arise.
    # For now, attempt standard installation.
    # Consider AMD-specific requirements if available in the repo, e.g., requirements_amd.txt
    if [ -f "requirements_rocm.txt" ]; then
        echo -e "${YELLOW}[INFO] Found requirements_rocm.txt. Using it for ROCm specific dependencies.${NC}"
        pip install -r requirements_rocm.txt
    elif [ -f "requirements_amd.txt" ]; then
        echo -e "${YELLOW}[INFO] Found requirements_amd.txt. Using it for AMD specific dependencies.${NC}"
        pip install -r requirements_amd.txt
    else
         echo -e "${YELLOW}[INFO] No ROCm/AMD specific requirements file found. Using generic requirements.txt.${NC}"
         pip install -r requirements.txt
    fi

    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR] Failed to install dependencies from requirements file.${NC}"
        echo -e "${YELLOW}You might need to check the text-generation-webui GitHub page for ROCm-specific installation instructions or troubleshooting.${NC}"
        deactivate
        exit 1
    fi
else
    echo -e "${RED}[ERROR] requirements.txt not found in $OOBABOOGA_DIR.${NC}"
    echo -e "${YELLOW}The repository structure might have changed. Please check the text-generation-webui GitHub page for installation instructions.${NC}"
    deactivate
    exit 1
fi

# Deactivate virtual environment
deactivate

echo -e "${GREEN}[SUCCESS] Oobabooga (text-generation-webui) installation script finished.${NC}"
echo -e "${YELLOW}Please check for any errors above.${NC}"
echo -e "${YELLOW}You can now try to start Oobabooga using the main menu.${NC}"
echo -e "${YELLOW}Note: You will need to download LLM models separately within the Oobabooga interface or manually.${NC}"
