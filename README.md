# ROCm WSL2 AI Toolkit

Simple, powerful toolkit for running AI image and video generation on AMD GPUs in WSL2. Uses the latest ROCm 6.4.2.1 and PyTorch 2.6.0.

## ✨ Features

- **Latest Stack**: ROCm 6.4.2.1 + PyTorch 2.6.0 (official AMD wheels)
- **WSL2 Optimized**: Designed specifically for Windows Subsystem for Linux 2
- **Ubuntu 24.04 Focus**: Primary support for Ubuntu 24.04, with Ubuntu 22.04 secondary
- **Simple Setup**: Clean TUI menu for easy installation and management
- **Automated**: Official AMD `amdgpu-install` method for reliable installation
- **AI Tools**: ComfyUI, SD.Next, and Automatic1111 support

## 🎯 Supported GPUs

- AMD Radeon RX 7000 series (RDNA3)
- AMD Radeon RX 9000 series (RDNA4)
- **Note**: Only RDNA3+ (gfx1100+) GPUs are supported

## 📋 Prerequisites

### Windows Requirements
- Windows 11 **or** Windows 10 with WSL2 support
- [AMD Adrenalin Edition 25.8.1 for WSL2](https://www.amd.com/en/resources/support-articles/release-notes/rn-rad-win-25-8-1.html) driver installed
- WSL2 enabled and configured

### WSL2 Requirements
- Ubuntu 24.04 (recommended) **or** Ubuntu 22.04
- At least 20GB free disk space
- Internet connection for downloads

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/daMustermann/rocm-wsl-ai.git
cd rocm-wsl-ai
```

### 2. Run the Menu

```bash
chmod +x menu.sh
./menu.sh
```

### 3. Install Base Environment

1. From the menu, select **Install** → **Base Environment**
2. Wait for installation to complete (10-20 minutes)
3. **IMPORTANT**: Restart WSL2
   ```powershell
   # In Windows PowerShell or CMD:
   wsl --shutdown
   ```
4. Restart your Ubuntu terminal

### 4. Install AI Tools

Run `./menu.sh` again and install your desired tools:
- **ComfyUI**: Node-based workflow for Stable Diffusion
- **SD.Next**: Advanced Stable Diffusion WebUI
- **Automatic1111**: Popular Stable Diffusion WebUI

### 5. Launch and Enjoy!

Use the **Launch Tool** menu to start your installed applications.

## 📖 Menu Options

### 📦 Install
- **Base Environment**: Installs ROCm 6.4.2.1 + PyTorch 2.6.0 + Python virtual environment
- **ComfyUI**: Node-based Stable Diffusion interface
- **SD.Next**: Feature-rich Stable Diffusion WebUI
- **Automatic1111**: Classic Stable Diffusion WebUI

### 🚀 Launch Tool
Start any installed AI application. The tool will automatically activate the Python environment and launch the web interface.

### 📊 System Status
View installation status of:
- Base environment (ROCm/PyTorch)
- Installed AI tools
- GPU detection status

### ❓ Help
Quick reference for setup and troubleshooting.

## 🛠️ What Gets Installed

### Base Environment Installation
1. **ROCm 6.4.2.1**: Via AMD's official `amdgpu-install` method
   - Graphics stack
   - HIP runtime
   - ROCm libraries
2. **Python Virtual Environment**: `~/genai_env`
3. **PyTorch 2.6.0**: Official AMD wheels from repo.radeon.com
   - torch, torchvision, torchaudio
   - pytorch-triton-rocm
4. **GPU Configuration**: Automatic HSA_OVERRIDE_GFX_VERSION detection

### Python Versions
- **Ubuntu 24.04**: Python 3.12
- **Ubuntu 22.04**: Python 3.10

## ⚙️ Technical Details

| Component | Version |
|-----------|---------|
| ROCm | 6.4.2.1 |
| PyTorch | 2.6.0+rocm6.4.2 |
| Triton | 3.2.0+rocm6.4.2 |
| Installation Method | amdgpu-install (official) |
| Python (24.04) | 3.12 |
| Python (22.04) | 3.10 |

## 🔧 Troubleshooting

### GPU Not Detected

**Symptoms**: `rocminfo` shows no GPU or PyTorch can't see ROCm

**Solutions**:
1. Verify AMD Adrenalin 25.8.1 is installed on Windows
2. Restart WSL2: `wsl --shutdown` (in PowerShell)
3. Check GPU in Windows: Open Radeon Software
4. Verify WSL2 is up to date: `wsl --update`

### Installation Fails

**Common Issues**:
- **No internet**: Check connection with `ping google.com`
- **Disk space**: Ensure 20GB+ free with `df -h`
- **Wrong Ubuntu**: This toolkit requires 24.04 or 22.04

### PyTorch Import Error

**Symptoms**: `ImportError` when importing torch

**Solutions**:
1. Ensure virtual environment is activated:
   ```bash
   source ~/genai_env/bin/activate
   ```
2. Reinstall base environment from menu
3. Check Python version matches Ubuntu (3.12 for 24.04, 3.10 for 22.04)

### Tools Won't Launch

**Symptoms**: Error when launching ComfyUI/SD.Next/Automatic1111

**Solutions**:
1. Verify base environment is installed (check System Status)
2. Ensure WSL2 was restarted after base installation
3. Try running tool manually to see detailed error:
   ```bash
   source ~/genai_env/bin/activate
   cd ~/ComfyUI  # or ~/SD.Next or ~/stable-diffusion-webui
   python main.py  # for ComfyUI
   ```

## 📚 Advanced Topics

### Manual Virtual Environment Activation

Each time you open a new terminal, activate the environment:
```bash
source ~/genai_env/bin/activate
```

### Updating Tools

AI tools can be updated individually:
```bash
source ~/genai_env/bin/activate
cd ~/ComfyUI  # or your tool directory
git pull
pip install -r requirements.txt  # if exists
```

### WSL2 Performance Tips

1. **Use Windows 11**: Better WSL2 GPU support
2. **Allocate RAM**: Edit `.wslconfig` in Windows user folder
   ```ini
   [wsl2]
   memory=16GB
   processors=8
   ```
3. **Store files in WSL**: Keep projects in `/home/` not `/mnt/c/`

## 📖 Additional Documentation

- **[WSL2 Setup Guide](docs/WSL2_SETUP_GUIDE.md)**: Detailed setup instructions
- **[Changelog](CHANGELOG.md)**: Version history and updates

## 🔗 Official Resources

- [AMD ROCm Documentation](https://rocm.docs.amd.com/)
- [AMD ROCm WSL Installation](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/install-radeon.html)
- [PyTorch ROCm Installation](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/install-pytorch.html)
- [AMD Compatibility Matrix](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/compatibility/compatibilityrad/compatibility.html)

## 🆘 Getting Help

1. Check **System Status** in the menu
2. Review troubleshooting section above
3. Check [AMD ROCm Documentation](https://rocm.docs.amd.com/)
4. Open an issue on GitHub with:
   - Ubuntu version (`lsb_release -a`)
   - GPU model
   - Error messages
   - Output of `rocminfo`

## 📄 License

MIT License - See LICENSE file for details

## 🙏 Acknowledgments

- AMD for ROCm and driver support
- PyTorch team for ROCm integration
- ComfyUI, SD.Next, and Automatic1111 communities
