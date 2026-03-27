# WSL2 Setup Guide for ROCm AI Toolkit

Complete guide for setting up AMD ROCm on WSL2 for AI workloads.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [WSL2 Installation](#wsl2-installation)
3. [Ubuntu Installation](#ubuntu-installation)
4. [AMD Driver Installation](#amd-driver-installation)
5. [ROCm Installation](#rocm-installation)
6. [PyTorch Installation](#pytorch-installation)
7. [Verification](#verification)
8. [Troubleshooting](#troubleshooting)

## Prerequisites

### Windows Requirements

- **Windows Version**: Windows 11
- **GPU**: AMD Radeon RX 7000 or RX 9000 series (RDNA3/RDNA4), or Ryzen Strix / Strix Halo APU
- **RAM**: 16GB+ recommended
- **Disk Space**: 30GB+ free space
- **AMD Adrenalin 26.2.2+ driver**: [Download](https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-26-2-2.html)
- **Windows SDK**: [Download](https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/) (required for ROCDXG build).  
  *Note: During SDK installation, check **"Windows SDK for Desktop C++ amd64 Apps"**. Leave its auto-selected dependencies checked, but you can uncheck Performance Toolkit, Debugging Tools, .NET, etc. to save space.*
  
  <img src="assets/winsdkinstall.png" width="600" alt="Windows SDK Installation Options">

### Check Windows Version

```powershell
# In PowerShell
winver
```

## Upgrading from v2.x (ROCm 7.2.0)

If you already have an existing ROCm 7.2.0 installation, use the built-in upgrade wizard:

```bash
cd rocm-wsl-ai
git pull
./menu.sh
# Select: Install Tools → Upgrade from ROCm 7.2.0 → 7.2.1 (ROCDXG)
```

**Before upgrading, install on Windows:**
1. AMD Adrenalin 26.2.2+ driver
2. Windows SDK *(Check "Desktop C++ amd64 Apps" and leave its auto-selected dependencies checked; uncheck the rest)*

<img src="assets/winsdkinstall.png" width="600" alt="Windows SDK Installation Options">

The upgrade wizard will back up your old venv, install ROCm 7.2.1 + ROCDXG, create a fresh Python environment, and reinstall all your AI tool dependencies. **Your models, custom nodes, and extensions are never touched.**

## WSL2 Installation

### Step 1: Enable WSL2

Open PowerShell as Administrator and run:

```powershell
wsl --install
```

This command will:
- Enable WSL feature
- Enable Virtual Machine Platform
- Install Ubuntu (default distribution)
- Set WSL 2 as default

### Step 2: Restart Computer

After installation completes, restart your computer.

### Step 3: Check WSL Version

After restart, verify WSL2 is active:

```powershell
wsl --list --verbose
```

Should show:
```
  NAME      STATE           VERSION
* Ubuntu    Running         2
```

If VERSION shows `1`, update to WSL2:
```powershell
wsl --set-version Ubuntu 2
```

### Step 4: Update WSL

```powershell
wsl --update
```

## Ubuntu Installation

If you need to install Ubuntu manually or want a specific version:

### Install Ubuntu 24.04 (Recommended)

```powershell
wsl --install -d Ubuntu-24.04
```

### Install Ubuntu 22.04 (Alternative)

```powershell
wsl --install -d Ubuntu-22.04
```

### Set Default Distribution

```powershell
wsl --set-default Ubuntu-24.04
```

### First Launch

1. Launch Ubuntu from Start Menu
2. Create your username and password (remember these!)
3. Wait for initial setup to complete

## AMD Driver Installation

### CRITICAL: Install Windows Driver First

You **MUST** install the AMD Adrenalin driver on Windows before ROCm will work in WSL2.

### Step 1: Download AMD Driver

Download [AMD Adrenalin Edition 26.2.2 or newer](https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-26-2-2.html)

### Step 2: Install Driver

1. Run the installer
2. Choose "Full Install" or "Minimal Install"
3. Restart Windows after installation

### Step 3: Verify Installation

1. Open AMD Radeon Software from System Tray
2. Check that your GPU is detected
3. Ensure WSL2 support is enabled in driver settings

## ROCm Installation

### Automated Installation (Recommended)

Use our toolkit for automated installation:

```bash
cd rocm-wsl-ai
chmod +x menu.sh
./menu.sh
# Select: Install → Base Environment
```

See [README.md](../README.md) for detailed toolkit usage.

### Manual Installation

If you prefer manual installation:

#### Step 1: Update System

```bash
sudo apt update
sudo apt upgrade -y
```

#### Step 2: Download amdgpu-install

**For Ubuntu 24.04:**
```bash
wget https://repo.radeon.com/amdgpu-install/7.2.1/ubuntu/noble/amdgpu-install_7.2.1.70201-1_all.deb
sudo apt install ./amdgpu-install_7.2.1.70201-1_all.deb
```

**For Ubuntu 22.04:**
```bash
wget https://repo.radeon.com/amdgpu-install/7.2.1/ubuntu/jammy/amdgpu-install_7.2.1.70201-1_all.deb
sudo apt install ./amdgpu-install_7.2.1.70201-1_all.deb
```

#### Step 3: Install ROCm

```bash
sudo apt update
sudo apt install -y python3-setuptools python3-wheel
sudo apt install -y rocm
```

**Note**: In ROCm 7.2.1, the install method changed from `amdgpu-install --usecase=wsl,rocm` to `apt install rocm`.

#### Step 4: Build & Install ROCDXG (librocdxg)

ROCDXG is the new user-mode bridge library that enables GPU compute in WSL via DXCore.

**Prerequisites**: Windows SDK must be installed on Windows.

```bash
# Install build dependencies
sudo apt install -y cmake gcc

# Clone librocdxg
git clone https://github.com/ROCm/librocdxg.git
cd librocdxg

# Set path to the Windows SDK Include directory dynamically
export win_kits="/mnt/c/Program Files (x86)/Windows Kits/10/Include"
export sdk_ver=$(ls -1 "$win_kits" | grep -E '^10\.' | sort -V | tail -1)
export win_sdk="${win_kits}/${sdk_ver}"
export CXXFLAGS="-I$win_sdk/shared -I$win_sdk/um"

mkdir -p build && cd build
cmake .. -DWIN_SDK="${win_sdk}/shared"
make
sudo make install
```

#### Step 5: Add User to Groups

```bash
sudo usermod -a -G render,video $USER
```

#### Step 6: Restart WSL2

**In Windows PowerShell:**
```powershell
wsl --shutdown
```

Then restart your Ubuntu terminal.

#### Step 7: Verify ROCm

```bash
export HSA_ENABLE_DXG_DETECTION=1
rocminfo
```

You should see your GPU listed with its marketing name (e.g., "Radeon RX 7900 XTX").

## PyTorch Installation

### Using Our Toolkit (Recommended)

The base environment installation includes PyTorch. No manual steps needed!

### Manual PyTorch Installation

If you prefer manual setup:

#### Step 1: Create Virtual Environment

```bash
python3 -m venv ~/genai_env
source ~/genai_env/bin/activate
pip install --upgrade pip wheel
```

#### Step 2: Download PyTorch Wheels

**For Ubuntu 24.04 (Python 3.12):**
```bash
cd /tmp
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/torch-2.9.1%2Brocm7.2.1.lw.gitff65f5bc-cp312-cp312-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/torchvision-0.24.0%2Brocm7.2.1.gitb919bd0c-cp312-cp312-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/torchaudio-2.9.0%2Brocm7.2.1.gite3c6ee2b-cp312-cp312-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/triton-3.5.1%2Brocm7.2.1.gita272dfa8-cp312-cp312-linux_x86_64.whl
```

**For Ubuntu 22.04 (Python 3.10):**
```bash
cd /tmp
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/torch-2.9.1%2Brocm7.2.1.lw.gitff65f5bc-cp310-cp310-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/torchvision-0.24.0%2Brocm7.2.1.gitb919bd0c-cp310-cp310-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/torchaudio-2.9.0%2Brocm7.2.1.gite3c6ee2b-cp310-cp310-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/triton-3.5.1%2Brocm7.2.1.gita272dfa8-cp310-cp310-linux_x86_64.whl
```

#### Step 3: Install Wheels

```bash
pip3 install torch-*.whl torchvision-*.whl torchaudio-*.whl triton-*.whl
rm -f *.whl
```

#### Step 4: WSL Runtime Fix

```bash
location=$(pip show torch | grep Location | awk -F ": " '{print $2}')
cd ${location}/torch/lib/
rm -f libhsa-runtime64.so*
```

## Verification

### Test ROCm

```bash
rocminfo
```

Expected output should include:
```
*******
Agent 2
*******
  Name:                    gfx1100
  Marketing Name:          Radeon RX 7900 XTX
  ...
```

### Test PyTorch

```bash
source ~/genai_env/bin/activate
python3 -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'ROCm available: {torch.cuda.is_available()}'); print(f'GPU count: {torch.cuda.device_count()}'); print(f'GPU name: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"N/A\"}')"
```

Expected output:
```
PyTorch: 2.9.1+rocm7.2.1
ROCm available: True
GPU count: 1
GPU name: Radeon RX 7900 XTX
```

## Troubleshooting

### GPU Not Detected in WSL2

**Problem**: `rocminfo` shows no GPU or "No AMD GPU detected"

**Solutions**:
1. **Verify Windows Driver**: Open AMD Radeon Software on Windows, ensure GPU is detected
2. **Check Driver Version**: Must be AMD Adrenalin 26.2.2 or newer
3. **Check ROCDXG**: Verify librocdxg is installed:
   ```bash
   ls /opt/rocm/lib/librocdxg.so
   ```
4. **Set ROCDXG env var**: Ensure HSA_ENABLE_DXG_DETECTION is set:
   ```bash
   export HSA_ENABLE_DXG_DETECTION=1
   ```
5. **Restart WSL2**:
   ```powershell
   wsl --shutdown
   ```
6. **Check WSL Version**:
   ```powershell
   wsl --list --verbose
   ```
   Must show VERSION 2, not 1
7. **Update WSL**:
   ```powershell
   wsl --update
   ```

### PyTorch Can't Find ROCm

**Problem**: `torch.cuda.is_available()` returns `False`

**Solutions**:
1. **Check ROCm Installation**:
   ```bash
   rocminfo | grep "Marketing Name"
   ```
2. **Verify Virtual Environment**:
   ```bash
   which python
   # Should show: /home/username/genai_env/bin/python
   ```
3. **Check HSA Override**:
   ```bash
   echo $HSA_OVERRIDE_GFX_VERSION
   # Should show: gfx1100 or gfx1200 or similar
   ```
4. **Reinstall PyTorch**: Use toolkit or manual method above

### ImportError: libhsa-runtime64.so

**Problem**: PyTorch fails to load with HSA runtime error

**Solution**: Apply WSL runtime fix:
```bash
source ~/genai_env/bin/activate
location=$(pip show torch | grep Location | awk -F ": " '{print $2}')
cd ${location}/torch/lib/
rm -f libhsa-runtime64.so*
```

### Permission Denied Errors

**Problem**: Can't access `/dev/kfd` or `/dev/dri`

**Solution**:
1. **Add to groups**:
   ```bash
   sudo usermod -a -G render,video $USER
   ```
2. **Restart WSL2**:
   ```powershell
   wsl --shutdown
   ```

### Slow Performance

**Solutions**:
1. **Increase WSL2 Memory**: Create/edit `C:\Users\YourName\.wslconfig`:
   ```ini
   [wsl2]
   memory=16GB
   processors=8
   swap=8GB
   ```
2. **Store Projects in WSL**: Use `/home/username/` not `/mnt/c/`
3. **Disable Windows Defender** for WSL2 folders (optional)

### Network Issues in WSL2

**Problem**: Can't download packages

**Solutions**:
1. **Check DNS**:
   ```bash
   cat /etc/resolv.conf
   ```
2. **Update DNS** (if needed):
   ```bash
   echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
   ```

### amdgpu-install Fails

**Problem**: Installation script errors

**Solutions**:
1. **Check Ubuntu Version**:
   ```bash
   lsb_release -a
   # Must be 24.04 or 22.04
   ```
2. **Update System First**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```
3. **Check Disk Space**:
   ```bash
   df -h
   # Ensure 20GB+ free
   ```

## Performance Tips

### Memory Allocation

Edit `C:\Users\YourName\.wslconfig`:
```ini
[wsl2]
memory=16GB          # Adjust based on your RAM
processors=8         # Adjust based on your CPU cores
swap=8GB
localhostForwarding=true
```

Restart WSL2 after editing.

### File System Performance

- Store git repositories in `/home/` (Linux filesystem)
- Avoid `/mnt/c/` (Windows filesystem) for large files
- Use `explorer.exe .` to open Windows Explorer from WSL2

### GPU Memory

Monitor GPU usage:
```bash
rocm-smi
```

### Networking

For web UIs (ComfyUI, etc.), access via:
- `http://localhost:PORT` from Windows
- Or find WSL2 IP: `hostname -I`

## Additional Resources

- [AMD ROCm Documentation](https://rocm.docs.amd.com/)
- [WSL2 Official Docs](https://docs.microsoft.com/en-us/windows/wsl/)
- [PyTorch ROCm Guide](https://pytorch.org/get-started/locally/)
- [Our Toolkit README](../README.md)

## Getting Help

If you encounter issues:

1. Check this guide's troubleshooting section
2. Verify all prerequisites are met
3. Check [AMD ROCm GitHub Issues](https://github.com/ROCm/ROCm/issues)
4. Open an issue on our repository with:
   - Output of `lsb_release -a`
   - Output of `rocminfo`
   - Exact error messages
   - Steps to reproduce

## Quick Reference Commands

```bash
# Check WSL version
wsl --list --verbose

# Shutdown WSL2
wsl --shutdown          # Run in PowerShell

# Check ROCm
rocminfo

# Check GPU
rocm-smi

# Activate venv
source ~/genai_env/bin/activate

# Check PyTorch
python3 -c "import torch; print(torch.cuda.is_available())"
```
