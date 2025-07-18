# ROCm-WSL-AI Update Summary - Juli 2025

## � Major Updates Applied

### Version Updates
- **ROCm:** Updated from 6.3 to **6.4.1** (latest stable)
- **PyTorch:** Updated from 2.7.1 to **2.8.0** (latest with ROCm support)
- **Support added:** Full **RDNA4 (RX 9000 series)** GPU support 🆕

### New Features
- ✅ **RDNA4 GPU Detection** - Automatic recognition of RX 9000 series
- ✅ **Improved GPU Architecture Detection** - Better handling of all AMD GPU generations
- ✅ **Updated Installation URLs** - Latest ROCm installer packages
- ✅ **Corrected HSA_OVERRIDE_GFX_VERSION values** - Proper gfx target identifiers

### Files Updated

#### Core Installation Scripts
1. **`1_setup_pytorch_rocm_wsl.sh`**
   - ROCm installer URL: `6.4.1/ubuntu/noble/amdgpu-install_6.4.60401-1_all.deb`
   - PyTorch version: `2.8.0` with ROCm `6.4` index
   - Added RDNA4 detection (gfx1200, gfx1201)
   - Enhanced GPU architecture detection

2. **`5_update_ai_setup.sh`**
   - Updated PyTorch installation command for ROCm 6.4
   - Corrected version numbers in update routines

3. **`6_install_automatic1111.sh`**
   - Updated PyTorch index URL to ROCm 6.4
   - Updated environment variable settings
   - Added RDNA4 support in launch scripts

4. **`8_install_invokeai.sh`**
   - Updated PyTorch extra-index-url for ROCm 6.4
   - Updated environment configurations

#### Documentation
5. **`README.md`**
   - Updated version numbers (ROCm 6.4.1, PyTorch 2.8.0)
   - Added RDNA4 (RX 9000 series) as "Cutting-edge performance"
   - Improved installation instructions with clearer GitHub clone steps
   - Corrected HSA_OVERRIDE_GFX_VERSION values to proper gfx targets
   - Enhanced troubleshooting section with current versions

## 🔧 To Use the Updated Scripts

In your Ubuntu/WSL terminal:

```bash
# Make scripts executable
chmod +x *.sh

# Start the main menu
./0_ai_tools_menu.sh
```

## 🎯 Installation Workflow

1. **Start with foundation**: Install ROCm/PyTorch (Option 1)
2. **Restart WSL**: `wsl --shutdown` in Windows PowerShell
3. **Choose AI tools**: Install ComfyUI, Automatic1111, Ollama, etc.
4. **Keep updated**: Use the update system regularly

## 🆕 New Features

- **Smart dependency checking** - Prevents installation conflicts
- **Update management** - Keep everything current
- **Multiple AI tools** - Choose what you need
- **Performance optimization** - GPU-specific configurations
- **Better error handling** - More informative messages
- **Service management** - Easy start/stop for tools

## 🎨 Available AI Tools

| Tool | Purpose | Access |
|------|---------|--------|
| ComfyUI | Node-based SD workflows | http://127.0.0.1:8188 |
| Automatic1111 | Popular SD interface | http://127.0.0.1:7860 |
| SD.Next | Advanced SD WebUI | Various ports |
| InvokeAI | Professional AI art | http://127.0.0.1:9090 |
| Ollama | Local AI chat | Terminal/Web interface |

## 🔄 Regular Maintenance

Use the update script to keep everything current:
```bash
./5_update_ai_setup.sh
```

This ensures:
- Latest ROCm drivers
- Current PyTorch versions
- Updated AI tools and extensions
- Clean system performance

All scripts are now ready for the 2025 AI development workflow! 🚀
