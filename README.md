# 🔥 ROCm-WSL-AI 2025 🚀

> **Supercharge your AMD GPU for AI in Windows Subsystem for Linux - 2025 Edition!**

This repository provides a streamlined setup for running AI workloads (like Stable Diffusion, Large Language Models, and more) on AMD GPUs using ROCm within Windows Subsystem for Linux (WSL2). **Updated for July 2025 with the latest tools and versions!**

## 🎯 Features

- ✅ **Latest ROCm 6.4.1** with PyTorch 2.8.0 support
- ✅ **RDNA4 Support** - Full support for RX 9000 series GPUs 🆕
- ✅ **Enhanced Installation System** with intelligent update capabilities
- ✅ **ComfyUI** with Manager for easy extension management
- ✅ **SD.Next** - Advanced Stable Diffusion WebUI
- ✅ **Automatic1111 WebUI** - Popular Stable Diffusion interface
- ✅ **Ollama** - Run large language models locally (Llama, Mistral, etc.)
- ✅ **InvokeAI** - Professional-grade AI image generation
- ✅ **Comprehensive Update System** - Keep everything current
- ✅ **Auto-detection** of AMD GPU architecture (RDNA4, RDNA3, RDNA2, RDNA1, Vega, Polaris)
- ✅ **Smart Installation Checks** - Prevents conflicts and redundant installs
- ✅ **Performance Optimization** guides for each tool
- ✅ Compatible with **Ubuntu 24.04 LTS**

## 🛠️ Scripts Overview

### 0️⃣ `0_ai_tools_menu.sh` - **Enhanced Main Menu** 🆕

The completely redesigned menu system provides an intuitive interface for all operations:

- **📦 Installation Menu** - Install any AI tool with dependency checking
- **▶️ Startup Menu** - Quick launch for all installed tools
- **🔄 Update System** - Comprehensive update management
- **📊 Status Dashboard** - Check installation and system status
- **🎨 Modern Interface** - Color-coded, user-friendly design
- **🔗 Dependency Management** - Automatic prerequisite checking

### 1️⃣ `1_setup_pytorch_rocm_wsl.sh` - **Updated Foundation** ⬆️

Enhanced setup script with latest versions:

- **ROCm 6.4.1** - Latest stable release with RDNA4 support
- **PyTorch 2.8.0** - Latest stable with ROCm support
- **RDNA4 Detection** - Automatic configuration for RX 9000 series
- **Improved GPU Detection** - Better architecture recognition
- **Enhanced Error Handling** - More robust installation process
- **Performance Optimizations** - Optimized for modern AMD GPUs

### 2️⃣ `2_install_comfyui.sh` - **ComfyUI Installation**

Installs ComfyUI with latest updates and ComfyUI Manager.

### 3️⃣ `3_start_comfyui.sh` - **ComfyUI Launcher**

Quick launcher for ComfyUI with proper environment setup.

### 4️⃣ `4_install_sdnext.sh` - **SD.Next Installation**

Installs SD.Next with ROCm optimization.

### 5️⃣ `5_update_ai_setup.sh` - **🆕 Comprehensive Update System**

**NEW!** Intelligent update system that handles:

- **ROCm Driver Updates** - Latest drivers and libraries
- **PyTorch Updates** - Latest ROCm-compatible versions
- **AI Tool Updates** - ComfyUI, SD.Next, extensions, and custom nodes
- **Dependency Management** - Ensures compatibility
- **Cache Cleanup** - Maintains system performance
- **Verification Testing** - Confirms everything works after updates

### 6️⃣ `6_install_automatic1111.sh` - **🆕 Automatic1111 WebUI**

**NEW!** Professional Stable Diffusion WebUI with:

- **ROCm Optimization** - Configured for AMD GPUs
- **Essential Extensions** - ControlNet, Image Browser, LoRA support
- **Memory Optimization** - Efficient VRAM usage
- **Easy Launch Scripts** - One-click startup

### 7️⃣ `7_install_ollama.sh` - **🆕 Local AI Chat Models**

**NEW!** Run large language models locally:

- **Local LLM Support** - Llama 3.2, Mistral, CodeLlama, and more
- **ROCm Acceleration** - GPU-accelerated inference
- **Model Management** - Easy download and management
- **Chat Interface** - Built-in chat capabilities
- **Web UI Option** - Optional ChatGPT-like interface
- **Service Management** - Automatic startup and management

### 8️⃣ `8_install_invokeai.sh` - **🆕 Professional AI Art**

**NEW!** Professional-grade AI image generation:

- **Advanced Features** - ControlNet, inpainting, outpainting
- **Node-based Workflow** - Visual workflow editor  
- **Batch Processing** - Efficient batch operations
- **Professional Interface** - Clean, intuitive design
- **Model Management** - Built-in model downloading and management

## 🚀 Getting Started

### Prerequisites

- Windows 11 with WSL2 enabled
- Ubuntu 24.04 LTS installed in WSL2
- Compatible AMD GPU:
  - **RDNA4 (RX 9000 series)** - Cutting-edge performance ⭐⭐
  - **RDNA3 (RX 7000 series)** - Best performance ⭐
  - **RDNA2 (RX 6000 series)** - Great performance
  - **RDNA1 (RX 5000 series)** - Good performance
  - **Vega (Vega 56/64, Radeon VII)** - Compatible
  - **Polaris (RX 400/500 series)** - Basic compatibility
- Latest AMD drivers installed in Windows

### Quick Installation

1. **Clone this repository:**
   ```bash
   git clone https://github.com/daMustermann/rocm-wsl-ai.git
   cd rocm-wsl-ai
   ```

2. **Make scripts executable:**
   ```bash
   chmod +x *.sh
   ```

3. **Start the interactive menu:**
   ```bash
   ./0_ai_tools_menu.sh
   ```

4. **Follow the installation process:**
   - Choose "Installation Menu" (Option 1)
   - Install ROCm/PyTorch first (Option 1 in Installation Menu)
   - **Important:** Restart WSL when prompted: `wsl --shutdown` in Windows PowerShell/CMD
   - Restart your Ubuntu terminal and run the menu again
   - Install your preferred AI tools (ComfyUI, Automatic1111, etc.)

### Alternative: Manual Installation

If you prefer manual installation:

```bash
# 1. Install ROCm and PyTorch (restart WSL when prompted)
./1_setup_pytorch_rocm_wsl.sh

# 2. Install ComfyUI
./2_install_comfyui.sh

# 3. Start ComfyUI
./3_start_comfyui.sh
```

## 🎨 Available AI Tools

### ComfyUI - Node-based Stable Diffusion
- **Install:** Installation Menu → Option 2
- **Start:** `./3_start_comfyui.sh` or Startup Menu → Option 1
- **Access:** http://127.0.0.1:8188
- **Features:** Advanced workflows, custom nodes, ComfyUI Manager

### Automatic1111 WebUI - Popular SD Interface  
- **Install:** Installation Menu → Option 4
- **Start:** Startup Menu → Option 3
- **Access:** http://127.0.0.1:7860
- **Features:** ControlNet, extensions, user-friendly interface

### SD.Next - Advanced SD WebUI
- **Install:** Installation Menu → Option 3  
- **Start:** Startup Menu → Option 2
- **Access:** Varies by configuration
- **Features:** Modern interface, advanced features

### InvokeAI - Professional AI Art
- **Install:** Installation Menu → Option 6
- **Start:** Startup Menu → Option 6
- **Access:** http://127.0.0.1:9090
- **Features:** Professional tools, batch processing, node editor

### Ollama - Local AI Chat Models
- **Install:** Installation Menu → Option 5
- **Start:** Startup Menu → Option 4 or `~/start_ollama_chat.sh`
- **Models:** Llama 3.2, Mistral, CodeLlama, and more
- **Features:** Local LLM inference, model management, chat interface

## � Updating Your Installation

Keep your AI tools up-to-date with the comprehensive update system:

```bash
./5_update_ai_setup.sh
```

**Or use the menu:** Main Menu → Option 3

The update system handles:
- ROCm driver updates
- PyTorch version updates  
- AI tool updates (ComfyUI, extensions, models)
- Dependency management
- Cache cleanup
- Installation verification

## 📊 Monitoring and Status

### Check Installation Status
```bash
# Via menu
./0_ai_tools_menu.sh → Option 4

# Check ROCm
rocminfo
rocm-smi

# Check PyTorch
source ~/genai_env/bin/activate
python3 -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'ROCm: {torch.cuda.is_available()}')"
```

### Performance Monitoring
```bash
# GPU usage
rocm-smi

# Memory usage  
rocm-smi --showmeminfo

# System resources
htop
```
## 🛠️ Troubleshooting

### Common Issues

**ROCm Installation Issues:**
```bash
# Check ROCm installation
rocminfo

# Verify group membership (restart WSL if added recently)
groups

# Reinstall ROCm if needed
sudo amdgpu-install -y --usecase=wsl,rocm --no-dkms
```

**PyTorch ROCm Issues:**
```bash
# Check PyTorch installation
source ~/genai_env/bin/activate
python3 -c "import torch; print(torch.__version__); print(torch.cuda.is_available())"

# Reinstall PyTorch if needed
pip install torch==2.8.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.4 --force-reinstall
```

**Memory Issues:**
- Reduce image resolution in AI tools
- Close other GPU-intensive applications
- Adjust VRAM settings in tool configurations
- Use CPU fallback for problematic operations

**Performance Issues:**
- Verify `HSA_OVERRIDE_GFX_VERSION` is set correctly for your GPU
- Use `rocm-smi` to monitor GPU utilization
- Check that ROCm drivers are properly loaded

### GPU-Specific Settings

**RDNA4 (RX 9000 series):**
```bash
export HSA_OVERRIDE_GFX_VERSION="gfx1200"  # For most RX 9000 cards
# Or gfx1201 for some variants
```

**RDNA3 (RX 7000 series):**
```bash
export HSA_OVERRIDE_GFX_VERSION="gfx1100"  # For RX 7900 series
# Or gfx1101 for RX 7800/7700, gfx1102 for RX 7600
```

**RDNA2 (RX 6000 series):**
```bash
export HSA_OVERRIDE_GFX_VERSION="gfx1030"  # For most RX 6000 cards
```

**RDNA1 (RX 5000 series):**
```bash
export HSA_OVERRIDE_GFX_VERSION="gfx1010"  # For most RX 5000 cards
```

**Vega:**
```bash
export HSA_OVERRIDE_GFX_VERSION="gfx900"  # For Vega 56/64
# Or gfx906 for Radeon VII
```

**Polaris (RX 400/500 series):**
```bash
export HSA_OVERRIDE_GFX_VERSION="gfx803"  # For most Polaris cards
```

## 📁 Directory Structure

```
~/genai_env/          # Python virtual environment
~/ComfyUI/            # ComfyUI installation
~/SD.Next/            # SD.Next installation  
~/stable-diffusion-webui/  # Automatic1111 WebUI
~/InvokeAI/           # InvokeAI installation
~/.ollama/            # Ollama models and data
```

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with clear description

## � License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- AMD for ROCm development
- ComfyUI team for the excellent UI
- Automatic1111 for the WebUI
- PyTorch team for ROCm support
- Ollama team for local LLM inference
- InvokeAI team for professional AI tools
- All the amazing open-source AI community

## 📞 Support

- **Issues:** Use GitHub Issues for bug reports
- **Discussions:** Use GitHub Discussions for questions
- **Updates:** Watch the repository for updates

---

**Happy AI development with your AMD GPU! 🎨🚀**
