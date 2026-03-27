# ROCm WSL2 AI Toolkit

**The painless, automated way to run stable, high-performance AI on AMD hardware.**

![ROCm WSL2 AI Toolkit Preview](docs/assets/preview.png)

## 🛑 The Problem: AMD AI on Windows is a Headache
If you've ever tried running Stable Diffusion or ComfyUI on an AMD Radeon graphics card in Windows, you know the struggle:
- **Native Windows ROCm** is often unsupported, lagging behind Linux in features, or fundamentally unstable.
- **WSL2 (Windows Subsystem for Linux)** is drastically faster and more stable, but requires complex terminal wizardry to properly pass-through the GPU and manually configure the drivers.
- **Dependency Hell**: Tracking down the exact python wheels, `HSA_OVERRIDE_GFX_VERSION` variables, and PyTorch builds that actually work together takes hours of forum searching.
- **VRAM Hostage Situations**: Forgetting to close a terminal window means Python permanently hogs your card's VRAM, completely crippling your Windows gaming or rendering performance until you hunt down the process.

## ⭐ The Solution: Make it Effortless
This toolkit was built to abstract away the Linux complexity. It provides a beautiful, keyboard-driven smart dashboard that fully automates the installation of AMD's ROCm 7.2.1 stack with ROCDXG and PyTorch 2.9.1 inside WSL2. 

**Why this makes your life easier:**
- **Zero Guesswork Installation**: It automatically queries your OS, downloads the exact AMD-official PyTorch wheels, and silos everything in an isolated virtual environment. You literally just press "Install".
- **Seamless Windows Integration**: It generates interactive `.bat` files straight to your Windows Desktop. Double-click the icon in Windows, and it silently boots the WSL backend and launches your AI tools without you ever touching a terminal.
- **💤 Smart Sleep VRAM Manager**: Your AI tools are automatically put into hibernation after 30 minutes of inactivity, instantly freeing 100% of your VRAM back to Windows! Simply refreshing your browser on port 8188 wakes the AI instantly back up.
- **✨ Magic Settings Auto-Tuner**: Unsure which PyTorch optimizations make your specific GPU fastest? The built-in tuner natively sweeps your hardware against different attention and caching profiles, isolates the mathematical winner, and permanently injects it into your launch scripts.
- **Gorgeous Status Dashboard**: Built with Charmbracelet's `gum`, giving you a highly readable, colorful interface with real-time hardware polling so you never have to guess if ROCm is actually working.

---

## 🎯 Supported GPUs

- AMD Radeon RX 7000 series (RDNA3)
- AMD Radeon RX 9000 series (RDNA4)
- AMD Ryzen Strix / Strix Halo APUs (NEW in 3.0.0)
- **Note**: Only RDNA3+ (gfx1100+) GPUs and supported Ryzen APUs are supported

## 📋 Prerequisites

### Windows Requirements
- Windows 11
- [AMD Adrenalin Edition 26.2.2 **or newer**](https://www.amd.com/en/support/download/drivers.html) driver installed
- [Windows SDK](https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/) installed (required for ROCDXG build)
- WSL2 enabled and configured

### WSL2 Requirements
- Ubuntu 24.04 (recommended) **or** Ubuntu 22.04
- At least 20GB free disk space
- Internet connection for downloads

---

## 🚀 Quick Start

### 0. Absolute Beginner? (Windows 1-Click Setup)
If you have absolutely no idea how to install WSL2 or Ubuntu, we wrote an automated Windows wizard for you.
Simply right-click the `Install_WSL_Ubuntu.bat` file in this repository and select **"Run as administrator"**. It will completely configure WSL2 and download Ubuntu 24.04 directly to your PC.

Once inside your new Ubuntu terminal, continue below:

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

Use the **Launch Tool** menu to start your installed applications, or use the **Create Desktop Shortcuts** option to add icons directly to your Windows desktop!

---

## ⬆️ Upgrading from v2.x (ROCm 7.2.0)

If you already have the toolkit installed with ROCm 7.2.0, you can upgrade to 7.2.1 + ROCDXG **without losing any of your AI tools, models, or custom nodes**.

### Before You Upgrade

On your **Windows** machine, install these two things:

1. **AMD Adrenalin 26.2.2+ driver or newer** — [Download here](https://www.amd.com/en/support/download/drivers.html)
2. **Windows SDK** — [Download here](https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/)
   *(During installation, check **"Windows SDK for Desktop C++ amd64 Apps"**. It will automatically select a few required dependencies—leave those checked, but you can uncheck everything else to save space).*
   
   <img src="docs/assets/winsdkinstall.png" width="600" alt="Windows SDK Installation Options">

### Run the Upgrade

```bash
cd rocm-wsl-ai
git pull        # Get the latest toolkit version
./menu.sh
# Select: Install Tools → Upgrade from ROCm 7.2.0 → 7.2.1 (ROCDXG)
```

The upgrade wizard will:
- ✅ **Back up** your old Python virtual environment (you can delete it later)
- ✅ **Install** ROCm 7.2.1 and build ROCDXG (librocdxg) from source
- ✅ **Create** a fresh venv with PyTorch 2.9.1+rocm7.2.1
- ✅ **Reinstall** all dependencies for your installed AI tools (ComfyUI, SD.Next, etc.)
- ✅ **Preserve** all your models, custom nodes, extensions, and configurations

> **Your models are SAFE.** They live in `~/ComfyUI/models/`, `~/stable-diffusion-webui/models/`, etc. — completely outside the Python environment. The upgrade never touches them.

### After the Upgrade

1. Restart WSL: `wsl --shutdown` (in PowerShell)
2. Relaunch Ubuntu and run `./menu.sh`
3. Launch your AI tools as usual — everything should work with the new ROCm 7.2.1 + ROCDXG stack

### What Changed (Technical)

| | Before (v2.x) | After (v3.0.0) |
|---|---|---|
| ROCm | 7.2.0 | 7.2.1 |
| WSL Bridge | Legacy roc4wsl | **ROCDXG (librocdxg)** |
| Install method | `amdgpu-install --usecase=wsl,rocm` | `apt install rocm` + librocdxg |
| Windows driver | Adrenalin 26.1.1 | **Adrenalin 26.2.2+** |
| Env var | — | `HSA_ENABLE_DXG_DETECTION=1` |
| GPU support | RDNA3+ discrete | + **Ryzen Strix/Halo APUs** |

---

## 🛠️ What Gets Installed

### Base Environment Installation
1. **ROCm 7.2.1**: Via AMD's official `amdgpu-install` quick-start method
   - ROCm packages installed via `apt install rocm`
2. **ROCDXG (librocdxg)**: Built from source ([GitHub](https://github.com/ROCm/librocdxg/))
   - User-mode WSL bridge library enabling GPU compute via DXCore
   - Replaces the legacy `roc4wsl` approach
3. **Python Virtual Environment**: Completely isolated in `~/genai_env`
4. **PyTorch 2.9.1**: Official AMD wheels from repo.radeon.com
   - `torch`, `torchvision`, `torchaudio`, `pytorch-triton-rocm`
5. **GPU Configuration**: Automatic `HSA_OVERRIDE_GFX_VERSION` + `HSA_ENABLE_DXG_DETECTION` setup

## ⚙️ Technical Details

| Component | Version |
|-----------|---------|
| ROCm | 7.2.1 |
| ROCDXG | librocdxg (built from source) |
| PyTorch | 2.9.1+rocm7.2.1 |
| Triton | 3.5.1+rocm7.2.1 |
| Installation Method | amdgpu-install + apt install rocm + librocdxg |
| WSL Bridge | ROCDXG (HSA_ENABLE_DXG_DETECTION=1) |

---

## 🔧 Troubleshooting

### GPU Not Detected
**Symptoms**: `rocminfo` shows no GPU or PyTorch can't see ROCm
**Solutions**:
1. Verify AMD Adrenalin 26.2.2 or newer is installed on Windows
2. Verify `HSA_ENABLE_DXG_DETECTION=1` is set in your environment
3. Check librocdxg is installed: `ls /opt/rocm/lib/librocdxg.so`
4. Restart WSL2: `wsl --shutdown` (in PowerShell)
5. Check GPU in Windows: Open Radeon Software
6. Verify WSL2 is up to date: `wsl --update`

### PyTorch Import Error
**Symptoms**: `ImportError` when importing torch
**Solutions**:
1. Ensure virtual environment is activated:
   ```bash
   source ~/genai_env/bin/activate
   ```
2. Reinstall base environment from menu

## 📄 License

MIT License

## 🙏 Acknowledgments

- AMD for ROCm and driver support
- PyTorch team for ROCm integration
- The incredible ComfyUI, SD.Next, and Automatic1111 open-source communities
