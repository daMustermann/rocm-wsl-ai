# Changelog

All notable changes to this project will be documented in this file.

## [3.0.0] - 2026-03-27

### 🎉 Major Release - ROCDXG Architecture Upgrade

AMD has replaced the legacy `roc4wsl` WSL approach with the new open-source **ROCDXG (librocdxg)** library in ROCm 7.2.1. This release fully adopts the new architecture.

### ✨ Added
- **ROCDXG (librocdxg) Support**: The base installer now builds and installs librocdxg from source, enabling GPU compute via Microsoft's DXCore interface
- **Upgrade Migration Wizard**: New menu option (`Install Tools → Upgrade`) safely migrates from ROCm 7.2.0 to 7.2.1 while preserving all AI tools, models, and custom nodes
- **Startup Upgrade Detection**: TUI automatically detects old ROCm without ROCDXG and shows a clear upgrade notice with instructions
- **Windows SDK Auto-Detection**: Automatically locates the Windows SDK path required for building librocdxg
- **`HSA_ENABLE_DXG_DETECTION=1`**: New environment variable automatically set in venv activation, GPU config, and all launch scripts
- **`has_rocdxg()` Helper**: New function in `lib/common.sh` to check for librocdxg installation
- **Ryzen Strix / Strix Halo APU Support**: First officially supported Ryzen APUs for WSL AI workloads

### 🔄 Changed
- **BREAKING**: ROCm 7.2.0 → **7.2.1** — uses `apt install rocm` instead of `amdgpu-install --usecase=wsl,rocm`
- **BREAKING**: Windows driver requirement bumped from Adrenalin 26.1.1 to **26.2.2+**
- **BREAKING**: Windows SDK now required as a prerequisite for ROCDXG build
- PyTorch wheels updated to `+rocm7.2.1` (new git hashes: `gitff65f5bc`)
- Wheel source URL updated to `rocm-rel-7.2.1`
- `sageattention` is now bundled natively into the base python environment by default
- All launch scripts (`comfyui.sh`, `sdnext.sh`, `automatic1111.sh`) now export `HSA_ENABLE_DXG_DETECTION=1`
- `gpu_config.sh` now exports `HSA_ENABLE_DXG_DETECTION=1` and writes it to `gpu.env`
- `update_ai_setup.sh` updated to target ROCm 7.2.1 PyTorch index URL
- Menu banner and help text updated to v3.0.0

### 📚 Documentation
- README updated with ROCDXG architecture, Ryzen APU support, Windows SDK prerequisite
- Troubleshooting updated with ROCDXG-specific guidance
- Technical details table updated with new component versions

### 🛠️ Technical Details
- amdgpu-install package: 7.2.1.70201-1
- PyTorch wheels: `torch-2.9.1+rocm7.2.1.lw.gitff65f5bc`
- Wheel source: `https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/`
- Triton version: 3.5.1+rocm7.2.1

### ⚠️ Migration Notes
For users upgrading from 2.x:
1. **Reinstall required** — the installation method has changed fundamentally
2. Install **Adrenalin 26.2.2+** driver on Windows (replaces 26.1.1)
3. Install the **Windows SDK** on Windows (new requirement for librocdxg build)
4. Existing PyTorch environments will need to be recreated with new `+rocm7.2.1` wheels

### 🔗 References
- [AMD ROCDXG WSL Guide](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/howto_wsl.html)
- [librocdxg GitHub](https://github.com/ROCm/librocdxg/)
- [ROCm Quick Start](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/quick-start.html)
- [AMD Adrenalin 26.2.2 Release Notes](https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-26-2-2.html)

---

## [2.2.0] - 2026-03-23

### 🐛 Fixed
- **PyTorch Installer Bug**: Fixed a URL-encoding mismatch where files containing `%2B` were incorrectly decoded during `wget`, causing the official AMD PyTorch wheels to fail installation on strict pip environments.

---

## [2.1.0] - 2026-03-23

### 🎉 Major New Features
- **1-Click Windows Setup Wizard**: Added `Install_WSL_Ubuntu.bat`, a fully automated Windows script that completely bootstraps the WSL2 kernel and a clean Ubuntu 24.04 instance for absolute beginners with zero Linux knowledge.
- **💤 Smart Sleep VRAM Manager**: AI processes like ComfyUI now automatically enter hibernation mode after 30 minutes of inactivity to entirely free up GPU VRAM! Hitting port 8188 wakes it seamlessly back up via a proxy splash screen.
- **✨ Magic Settings Auto-Tuner**: New TUI dashboard option that actively runs PyTorch benchmark sweeps to perfectly optimize AMD arguments (`PYTORCH_HIP_ALLOC_CONF` and `MIGRAPHX`) for your specific GPU architecture.

### ✨ Added
- **Gorgeous TUI Upgrade**: Replaced standard whiptail menus with Charmbracelet `gum` for a highly styled, modern, and beautiful terminal interface.
- **Windows Desktop Shortcuts**: New menu option to automatically generate `wsl.exe` `.bat` shortcuts on the Windows Desktop for launching AI tools with one click.
- Automatic installation of `gum` dependency.

### 🔄 Changed
- Refactored `menu.sh` and `lib/common.sh` logging to use colored `gum style` blocks.
- Improved help and status readability.

---

## [2.0.0] - 2026-03-02

### 🎉 Major Release - Complete Overhaul

This release represents a complete overhaul of the ROCm WSL2 AI toolkit, focusing on the latest AMD stack and improved user experience.

### ✨ Added
- **ROCm 7.2.0** support (latest stable from AMD)
- **PyTorch 2.9.1** with official AMD wheels from repo.radeon.com
- **Ubuntu 24.04** as primary platform (Python 3.12)
- **New Simplified TUI** - Clean, modern menu system with emoji icons
- **Comprehensive WSL2 Setup Guide** (docs/WSL2_SETUP_GUIDE.md)
- Automatic Ubuntu version detection (noble/jammy)
- Automatic Python version selection (3.12/3.10)
- Official AMD `amdgpu-install` installation method
- WSL-specific runtime library fixes
- Enhanced status checking with detailed system information
- Quick help menu with essential information

### 🔄 Changed
- **BREAKING**: Now uses AMD's official `amdgpu-install` method instead of manual repository management
- **BREAKING**: Primary target is now Ubuntu 24.04 with Python 3.12 (22.04 still supported)
- **BREAKING**: Removed all deprecated `apt-key` usage
- Updated from PyTorch nightly index URLs to official AMD wheel downloads
- Simplified menu system - removed complex version selection
- Improved error messages with links to AMD documentation
- Better WSL2 detection and configuration
- Enhanced verification steps after installation

### 📚 Documentation
- Completely rewritten README.md with WSL2 focus
- New comprehensive WSL2_SETUP_GUIDE.md with troubleshooting
- Updated all version references to ROCm 7.2.0 and PyTorch 2.9.1
- Added quick start guide
- Added troubleshooting section
- Added performance tips for WSL2
- Updated links to AMD official documentation

### 🗑️ Removed
- Manual ROCm repository management (replaced with amdgpu-install)
- Deprecated apt-key commands
- Complex version selection menus
- Native Linux installation path (WSL2 focused)
- Outdated version detection from repo.radeon.com

### 🛠️ Technical Details
- Installation script: `scripts/install/setup_pytorch_rocm.sh`
- amdgpu-install package: 7.2.70200-1
- PyTorch wheels: cp312 (Ubuntu 24.04), cp310 (Ubuntu 22.04)
- Wheel source: https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/
- Triton version: 3.5.1+rocm7.2.0

### 📦 Wheel Downloads
**Ubuntu 24.04 (Python 3.12):**
- torch-2.9.1+rocm7.2.0
- torchvision-0.24.0+rocm7.2.0
- torchaudio-2.9.0+rocm7.2.0
- triton-3.5.1+rocm7.2.0

**Ubuntu 22.04 (Python 3.10):**
- torch-2.9.1+rocm7.2.0
- torchvision-0.24.0+rocm7.2.0
- torchaudio-2.9.0+rocm7.2.0
- triton-3.5.1+rocm7.2.0

### ⚠️ Migration Notes
For users upgrading from 1.x:

1. The installation method has changed - now uses AMD's official `amdgpu-install`
2. Existing installations may need to be reinstalled
3. Ubuntu 24.04 is now the recommended platform
4. PyTorch is now installed via official wheels, not nightlies

### 🔗 References
- [AMD ROCm WSL Installation Guide](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/install-radeon.html)
- [AMD PyTorch Installation Guide](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/native_linux/install-pytorch.html)
- [AMD Adrenalin 26.1.1 Release Notes](https://www.amd.com/en/resources/support-articles/release-notes/rn-rad-win-26-1-1.html)

---

## [1.0.0] - 2025-09-13

### Added
- Initial formal release entry (1.0.0)

### Changed
- ComfyUI installer now automatically clones and installs ComfyUI-Manager and ComfyUI-Lora-Manager
- Automatic1111 installer now clones/pulls latest repository and upgrades requirements
- SD.Next installer now clones/pulls latest repository and upgrades requirements
- ROCm / PyTorch install flows hardened for RDNA3+ hardware (gfx11xx/gfx12xx)

### Removed
- Support for InvokeAI, Fooocus, and SD WebUI Forge to reduce maintenance surface

### Documentation
- README.md updated to reflect supported tools

### Notes
- Baseline version numbering as 1.0.0



