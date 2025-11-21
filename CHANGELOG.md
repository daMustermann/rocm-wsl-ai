# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2025-11-21

### 🎉 Major Release - Complete Overhaul

This release represents a complete overhaul of the ROCm WSL2 AI toolkit, focusing on the latest AMD stack and improved user experience.

### ✨ Added
- **ROCm 6.4.2.1** support (latest stable from AMD)
- **PyTorch 2.6.0** with official AMD wheels from repo.radeon.com
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
- Updated all version references to ROCm 6.4.2.1 and PyTorch 2.6.0
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
- amdgpu-install package: 6.4.60402-1
- PyTorch wheels: cp312 (Ubuntu 24.04), cp310 (Ubuntu 22.04)
- Wheel source: https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.2/
- Triton version: 3.2.0+rocm6.4.2

### 📦 Wheel Downloads
**Ubuntu 24.04 (Python 3.12):**
- torch-2.6.0+rocm6.4.2
- torchvision-0.21.0+rocm6.4.2
- torchaudio-2.6.0+rocm6.4.2
- pytorch_triton_rocm-3.2.0+rocm6.4.2

**Ubuntu 22.04 (Python 3.10):**
- torch-2.6.0+rocm6.4.2
- torchvision-0.21.0+rocm6.4.2
- torchaudio-2.6.0+rocm6.4.2
- pytorch_triton_rocm-3.2.0+rocm6.4.2

### ⚠️ Migration Notes
For users upgrading from 1.x:

1. The installation method has changed - now uses AMD's official `amdgpu-install`
2. Existing installations may need to be reinstalled
3. Ubuntu 24.04 is now the recommended platform
4. PyTorch is now installed via official wheels, not nightlies

### 🔗 References
- [AMD ROCm WSL Installation Guide](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/install-radeon.html)
- [AMD PyTorch Installation Guide](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/install-pytorch.html)
- [AMD Adrenalin 25.8.1 Release Notes](https://www.amd.com/en/resources/support-articles/release-notes/rn-rad-win-25-8-1.html)

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



