
## 🔥 ROCm-WSL-AI 2025

Make your AMD GPU sing inside WSL2. This repo gives you a slick terminal menu for installing, launching, updating, and removing popular local AI tools — and it keeps your stack fresh with the latest ROCm and PyTorch Nightly.

## What you get
- Always latest ROCm (from AMD’s “latest” apt repo) + PyTorch Nightly matched to your installed ROCm series
- A modern, keyboard-driven TUI (whiptail) with clear categories and no duplicate installs
- One place to install, start, update, and remove local AI tools (image gen + LLMs)
- GitHub self-update for the menu itself

## Tools included (by category)
Image generation
- ComfyUI
- SD.Next
- Automatic1111 WebUI
- InvokeAI
- Fooocus
- SD WebUI Forge

LLMs
- Ollama (with a small model manager script)
- Text Generation WebUI
- llama.cpp
- KoboldCpp
- FastChat

System & utilities
- AMD GPU Drivers / ROCm
- Base setup: ROCm & PyTorch Nightly
- Updates (drivers, ROCm libs, PyTorch Nightly, tools)
- Status checks & basic verification
- Remove (uninstall) tools
- Self-update (pull latest from GitHub)

## Requirements
- Windows 11 + WSL2
- Ubuntu 24.04 inside WSL2
- AMD GPU (WSL passthrough for ROCm currently ONLY RDNA4 & RDNA3 – RDNA2 and older are not exposed as compute devices in WSL; for those use native Linux)
- whiptail (for the TUI). If the menu doesn’t render as a UI:
   ```bash
   sudo apt update && sudo apt install -y whiptail
   ```

### GPU Compatibility (WSL vs. Native Linux)

| Architecture / Generation | Example Series | WSL GPU Compute (ROCm) | Native Linux ROCm |
|---------------------------|----------------|------------------------|-------------------|
| RDNA4 (gfx12xx)          | RX 9000*       | ✅ Supported            | ✅ Supported       |
| RDNA3 (gfx11xx)          | RX 7000        | ✅ Supported            | ✅ Supported       |
| RDNA2 (gfx10.3)          | RX 6000        | ❌ Not passed through   | ✅ Supported       |
| RDNA1 (gfx10.1)          | RX 5000        | ❌ Not passed through   | ✅ Supported       |
| Vega (gfx9xx)            | Radeon VII     | ❌ Not passed through   | ✅ Supported       |
| Polaris (gfx803)         | RX 4xx / 5xx   | ❌ Not passed through   | ✅ Supported       |
| Older (GCN < gfx803)     | Various        | ❌ Not passed through   | ❌ / Partial       |

*Some very new RDNA4 SKUs may appear before AMD updates the official list.

Important:
- If your GPU is below RDNA3 it will show up inside WSL2 as a generic "Microsoft Basic Render Device" (or similar) and is not exposed for ROCm compute.
- You can still use the menu (CPU workflows / prep for a future upgrade), but GPU acceleration requires native Linux or RDNA3 / RDNA4 hardware under WSL.
- AMD reference: https://rocm.docs.amd.com/projects/radeon/en/latest/docs/compatibility/wsl/wsl_compatibility.html


## Install the suite
```bash
git clone https://github.com/daMustermann/rocm-wsl-ai.git
cd rocm-wsl-ai
chmod +x *.sh
./0_ai_tools_menu.sh
```

If prompted to restart WSL during base setup (after adding your user to the render/video groups), run this in Windows PowerShell/CMD and reopen Ubuntu:
```powershell
wsl --shutdown
```

## The menu (how to use)
Use arrow keys + Enter to select; Esc cancels a dialog.

- Installation
   - System → AMD GPU Drivers / ROCm (optional if you already have it)
   - Base → ROCm & PyTorch Nightly (do this first)
   - Then pick your favorite tools in Image generation or LLMs
   - Already installed tools won’t offer a second install

- Launch
   - Starts only tools that are detected as installed

- Updates
   - PyTorch Nightly (matched to your ROCm), ROCm libs, tools (ComfyUI, SD.Next, A1111, InvokeAI, Ollama, Fooocus, TextGen, etc.)
   - Full driver reinstall flow when needed

- Status
   - Quick checks for ROCm, PyTorch, and what’s installed

- Remove
   - Safe, confirmed removal of a selected tool’s folder

- Self-update
   - Pulls latest changes from GitHub and refreshes the menu itself

## Typical first run
1) Installation → Base (ROCm & PyTorch Nightly)
2) Restart WSL if asked
3) Installation → Pick your tools (e.g., ComfyUI, A1111, Ollama)
4) Launch → Start your tools

## Upgrading
Menu → Updates lets you:
- Update PyTorch Nightly to match your currently installed ROCm
- Update tools (ComfyUI, SD.Next, A1111, InvokeAI, Ollama, Fooocus, TextGen, …)
- Reinstall drivers (when required), and verify everything

Update the menu/repo itself with Self-update — or manually:
```bash
git pull --rebase
```

## Useful tips
- If the TUI looks very plain, install whiptail (see Requirements)
- If you changed groups during base install: restart WSL (`wsl --shutdown` from Windows)
- Ollama’s systemd user service may require systemd in WSL; if it doesn’t start, run it manually via the scripts
- For ROCm trouble, use the menu’s Driver Management and follow the prompts

```
## � Automatic GPU Detection

You normally do NOT need to manually set `HSA_OVERRIDE_GFX_VERSION` or `PYTORCH_ROCM_ARCH`.

On first run of any installer/launcher script the system:
1. Detects your AMD GPU architecture (`gfx*`) via `rocminfo` / `dmesg` hints
2. Maps it to the correct ROCm triplet (e.g. RDNA3 → `11.0.0`, RDNA4 → `12.0.0`)
3. Writes the resolved variables to:
   `~/.config/rocm-wsl-ai/gpu.env`
4. All subsequent scripts simply source that file

Want to re-detect? Delete the file:
```bash
rm ~/.config/rocm-wsl-ai/gpu.env
```
Then run the menu again; a fresh detection will occur.

Override manually? Edit the file directly. Example custom override:
```bash
echo 'export HSA_OVERRIDE_GFX_VERSION="11.0.0"' >> ~/.config/rocm-wsl-ai/gpu.env
```

Note: Under WSL only RDNA3/RDNA4 are exposed for compute. If you are on unsupported hardware the detection will fall back to a safe default and PyTorch may operate in reduced / CPU modes.

## �🛠️ Troubleshooting

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

### GPU-Specific Settings (Manual Override)

Normally handled automatically (see Automatic GPU Detection). Only use this if you are debugging or forcing a different mapping. Add one of these lines to `~/.config/rocm-wsl-ai/gpu.env` and then re-run the menu.

RDNA4 (RX 9000): `export HSA_OVERRIDE_GFX_VERSION="gfx1200"` (or `gfx1201`)
RDNA3 (RX 7000): `export HSA_OVERRIDE_GFX_VERSION="gfx1100"` (7800/7700: `gfx1101`, 7600: `gfx1102`)
RDNA2 (RX 6000): `export HSA_OVERRIDE_GFX_VERSION="gfx1030"`
RDNA1 (RX 5000): `export HSA_OVERRIDE_GFX_VERSION="gfx1010"`
Vega (56/64): `export HSA_OVERRIDE_GFX_VERSION="gfx900"` (Radeon VII: `gfx906`)
Polaris (RX 400/500): `export HSA_OVERRIDE_GFX_VERSION="gfx803"`

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

## 📄 License

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
