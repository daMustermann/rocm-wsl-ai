# 🔥 ROCm-WSL-AI 🚀

> **Supercharge your AMD GPU for AI in Windows Subsystem for Linux!**

This repository provides a streamlined setup for running AI workloads (like Stable Diffusion) on AMD GPUs using ROCm within Windows Subsystem for Linux (WSL2).

Try the "Other GPU" branch if you got a Radeon GPU that is not a 7900XTX and report back!

## 🎯 Features

- ✅ Automated ROCm installation for WSL2
- ✅ PyTorch with ROCm support setup
- ✅ ComfyUI installation and configuration
- ✅ ComfyUI Manager for easy extension management
- ✅ SD.Next installation and configuration
- ✅ Auto-detection of AMD GPU architecture
- ✅ Support for RDNA3, RDNA2, RDNA1, Vega, and Polaris GPUs
- ✅ Compatible with Ubuntu 24.04 LTS

## 🛠️ Scripts Overview

### 0️⃣ `0_ai_tools_menu.sh`

This combined menu script provides an easy-to-use interface for all installation and startup tasks:

- Unified menu for all AI tools installation
- Option to install ROCm and PyTorch (required first)
- ComfyUI installation and startup
- SD.Next installation and startup
- Installation status checks
- Color-coded output for better readability
- Handles dependencies between components

### 1️⃣ `1_setup_pytorch_rocm_wsl.sh`

This script sets up the foundation for AI development with AMD GPUs:

- Auto-detects your AMD GPU model and architecture
- Configures the appropriate settings for your specific GPU
- Installs AMD ROCm drivers for WSL2
- Configures necessary user groups
- Creates a Python virtual environment (`genai_env`)
- Installs PyTorch with ROCm support
- Installs Triton for optimized performance
- Performs verification checks to ensure everything is working

### 2️⃣ `2_install_comfyui.sh`

This script installs ComfyUI, a powerful UI for Stable Diffusion, along with ComfyUI Manager:

- Activates the previously created virtual environment
- Clones the ComfyUI repository
- Installs all required Python dependencies
- Installs ComfyUI Manager for easy extension and model management
- Provides instructions for running ComfyUI

### 3️⃣ `3_start_comfyui.sh`

A convenience script to easily start ComfyUI:

- Activates the Python virtual environment
- Navigates to the ComfyUI directory
- Launches ComfyUI with any provided arguments
- Handles error checking and proper environment setup

### 4️⃣ `4_install_sdnext.sh`

This script installs SD.Next, another powerful UI for Stable Diffusion:

- Verifies ROCm and PyTorch installation
- Clones the SD.Next repository
- Configures SD.Next for AMD GPU support
- Provides instructions for running SD.Next with ROCm

## 🚀 Getting Started

### Prerequisites

- Windows 11 with WSL2 enabled
- Ubuntu 24.04 LTS installed in WSL2
- Compatible AMD GPU:
  - RDNA3 (RX 7000 series) - Best performance
  - RDNA2 (RX 6000 series) - Great performance
  - RDNA1 (RX 5000 series) - Good performance
  - Vega (Vega 56/64, Radeon VII) - Compatible
  - Polaris (RX 400/500 series) - Basic compatibility
- Latest AMD drivers installed in Windows

### Installation Steps

1. Clone this repository:
   ```bash
   git clone https://github.com/daMustermann/rocm-wsl-ai.git
   cd rocm-wsl-ai
   ```

2. Make the scripts executable:
   ```bash
   chmod +x *.sh
   ```

3. (Recommended) Use the menu interface:
   ```bash
   ./0_ai_tools_menu.sh
   ```
   > 💡 **Tip**: The menu script provides an interactive interface for all installation and startup tasks

4. (Alternative) Run individual scripts in sequence:
   ```bash
   ./1_setup_pytorch_rocm_wsl.sh
   ```
   > ⚠️ **Note**: You'll need to restart WSL during this process when prompted.

4. Install ComfyUI:
   ```bash
   ./2_install_comfyui.sh
   ```

5. Start ComfyUI:
   ```bash
   ./3_start_comfyui.sh
   ```
   > 💡 **Tip**: You can pass additional arguments to ComfyUI, e.g., `./3_start_comfyui.sh --listen --port 8188`

6. Alternatively, install SD.Next:
   ```bash
   ./4_install_sdnext.sh
   ```
   > 💡 **Tip**: After installation, you can run SD.Next with `cd ~/SD.Next && ./webui.sh --use-rocm`


## 🖼️ Using ComfyUI

After starting ComfyUI:

1. Open your browser and navigate to `http://127.0.0.1:8188`
2. Click on the "Manager" button in the top menu to access ComfyUI Manager
3. Use ComfyUI Manager to easily install custom nodes and models
4. Download additional models into the appropriate folders in `~/ComfyUI/models/`
5. Create amazing AI-generated images with your AMD GPU!

## 🎨 Using SD.Next

After starting SD.Next:

1. Open your browser and navigate to `http://127.0.0.1:7860`
2. SD.Next offers multiple UI options (Standard and Modern)
3. Use the built-in model downloader to get Stable Diffusion models
4. Explore the extensive settings and features for image generation
5. Enjoy advanced features like ControlNet, LoRA support, and more

## 🔄 Updating

- To update ComfyUI: Navigate to the ComfyUI directory and run `git pull`
- To update ComfyUI Manager: Navigate to the ComfyUI Manager directory (`~/ComfyUI/custom_nodes/comfyui-manager`) and run `git pull`
- To update custom nodes: Use the "Update All" button in ComfyUI Manager
- To update SD.Next: Navigate to the SD.Next directory (`~/SD.Next`) and run `git pull`
- To update ROCm/PyTorch: Refer to the AMD documentation for the latest instructions

## 🤝 Contributing

Contributions are welcome! Feel free to submit issues or pull requests.

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgements

- [ComfyUI](https://github.com/comfyanonymous/ComfyUI) - The powerful and modular Stable Diffusion UI
- [ComfyUI Manager](https://github.com/Comfy-Org/ComfyUI-Manager) - Extension for managing ComfyUI custom nodes and models
- [SD.Next](https://github.com/vladmandic/sdnext) - Advanced fork of Stable Diffusion web UI
- [AMD ROCm](https://www.amd.com/en/graphics/servers-solutions-rocm) - AMD's open software platform for GPU computing
- [PyTorch](https://pytorch.org/) - The machine learning framework
