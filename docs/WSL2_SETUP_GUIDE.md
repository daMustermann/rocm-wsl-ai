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

- **Windows Version**: Windows 11 (recommended) or Windows 10 version 2004+ (Build 19041+)
- **GPU**: AMD Radeon RX 7000 or RX 9000 series (RDNA3/RDNA4)
- **RAM**: 16GB+ recommended
- **Disk Space**: 30GB+ free space

### Check Windows Version

```powershell
# In PowerShell
winver
```

Should show Build 19041 or higher for Windows 10, or any Windows 11 build.

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

Download [AMD Adrenalin Edition 25.8.1 for WSL2](https://www.amd.com/en/resources/support-articles/release-notes/rn-rad-win-25-8-1.html)

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
wget https://repo.radeon.com/amdgpu-install/6.4.2.1/ubuntu/noble/amdgpu-install_6.4.60402-1_all.deb
sudo apt install ./amdgpu-install_6.4.60402-1_all.deb
```

**For Ubuntu 22.04:**
```bash
wget https://repo.radeon.com/amdgpu-install/6.4.2.1/ubuntu/jammy/amdgpu-install_6.4.60402-1_all.deb
sudo apt install ./amdgpu-install_6.4.60402-1_all.deb
```

#### Step 3: Install ROCm

```bash
sudo amdgpu-install -y --usecase=wsl,rocm --no-dkms
```

**Note**: `--no-dkms` flag is required for WSL2 (no kernel module compilation needed).

#### Step 4: Add User to Groups

```bash
sudo usermod -a -G render,video $USER
```

#### Step 5: Restart WSL2

**In Windows PowerShell:**
```powershell
wsl --shutdown
```

Then restart your Ubuntu terminal.

#### Step 6: Verify ROCm

```bash
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
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.2/torch-2.6.0%2Brocm6.4.2.git76481f7c-cp312-cp312-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.2/torchvision-0.21.0%2Brocm6.4.2.git4040d51f-cp312-cp312-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.2/torchaudio-2.6.0%2Brocm6.4.2.gitd8831425-cp312-cp312-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.2/pytorch_triton_rocm-3.2.0%2Brocm6.4.2.git7e948ebf-cp312-cp312-linux_x86_64.whl
```

**For Ubuntu 22.04 (Python 3.10):**
```bash
cd /tmp
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.2/torch-2.6.0%2Brocm6.4.2.git76481f7c-cp310-cp310-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.2/torchvision-0.21.0%2Brocm6.4.2.git4040d51f-cp310-cp310-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.2/torchaudio-2.6.0%2Brocm6.4.2.gitd8831425-cp310-cp310-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.2/pytorch_triton_rocm-3.2.0%2Brocm6.4.2.git7e948ebf-cp310-cp310-linux_x86_64.whl
```

#### Step 3: Install Wheels

```bash
pip3 install torch-*.whl torchvision-*.whl torchaudio-*.whl pytorch_triton_rocm-*.whl
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
PyTorch: 2.6.0+rocm6.4.2
ROCm available: True
GPU count: 1
GPU name: Radeon RX 7900 XTX
```

## Troubleshooting

### GPU Not Detected in WSL2

**Problem**: `rocminfo` shows no GPU or "No AMD GPU detected"

**Solutions**:
1. **Verify Windows Driver**: Open AMD Radeon Software on Windows, ensure GPU is detected
2. **Check Driver Version**: Must be AMD Adrenalin 25.8.1 or newer
3. **Restart WSL2**:
   ```powershell
   wsl --shutdown
   ```
4. **Check WSL Version**:
   ```powershell
   wsl --list --verbose
   ```
   Must show VERSION 2, not 1
5. **Update WSL**:
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
