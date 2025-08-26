# ROCm AI Toolkit for Image & Video Generation

This repository provides a powerful, menu-driven toolkit to simplify the setup of a comprehensive AI environment for **image and video generation** on Linux. It's designed for AMD GPUs, using ROCm to unlock their full potential on both native Linux (Ubuntu) and WSL2.

The toolkit automates the entire process, from driver installation to application management, ensuring you have a stable, up-to-date environment with just a few commands.

## Why Use This Toolkit?

-   **Automated & Simple:** Gone are the days of manual dependency hell. A user-friendly terminal menu guides you through every step.
-   **Smart GPU Detection:** Automatically detects your AMD GPU and configures the environment with the correct settings (`HSA_OVERRIDE_GFX_VERSION`), simplifying setup for a wide range of RDNA, Vega, and Polaris cards.
-   **Always Up-to-Date:** The scripts automatically fetch the latest stable ROCm drivers and the correct PyTorch nightly builds, so you're always on the cutting edge.
-   **Robust & Isolated:** Manages a dedicated Python virtual environment to prevent conflicts with your system packages.
-   **Cross-Platform:** Works consistently on both native Ubuntu 22.04/24.04 and WSL2.
-   **Smart Updates:** A built-in, unified update system keeps both the toolkit and all your installed AI applications current with a single command.

## Supported Tools

This toolkit is focused on the best open-source applications for creative AI:

-   ComfyUI
-   Stable Diffusion WebUI (Automatic1111)
-   SD.Next
-   InvokeAI
-   Fooocus
-   SD WebUI Forge

## Getting Started

Follow these steps to get up and running in minutes.

### 1. Clone the Repository

First, clone this repository to your local machine and navigate into the directory:
```bash
git clone https://github.com/daMustermann/rocm-wsl-ai.git
cd rocm-wsl-ai
```

### 2. Run the Menu

First, make the menu.sh executable:
```bash
chmod +x menu.sh
```

Next, launch the main menu script:
```bash
./menu.sh
```
The script will automatically handle permissions for all its helper scripts.

### 3. Perform the Base Installation

This is the most important first step. It sets up the core ROCm and PyTorch environment that all other tools will use.

-   From the main menu, select `Manage Tools`.
-   Choose `Install a new tool`.
-   Select **`Base Installation (ROCm & PyTorch)`**.

You will be presented with a choice for the ROCm and PyTorch versions:
-   **`Latest stable ROCm (recommended) + PyTorch for ROCm Nightly`**: This is the recommended option for most users. It installs the latest stable ROCm drivers from the AMD repository and a matching PyTorch nightly build.

The script will then handle everything:
-   Installs the necessary AMD drivers and ROCm stack.
-   Creates a self-contained Python virtual environment at `~/genai_env`.
-   Installs the chosen compatible PyTorch nightly build and Triton.

**A system restart is required** after this step is complete to ensure all driver and user-group changes take effect.

### 4. Install Your Favorite Tools

After restarting, run `./menu.sh` again. Navigate back to `Manage Tools` -> `Install a new tool` and select any of the supported AI applications to install them.

## How It Works

The toolkit is centered around the `menu.sh` script, which provides a simple interface for complex tasks.

-   **Launch an AI tool:** Start any installed application.
-   **Manage Tools (Install / Uninstall):** Add or remove AI applications. The base environment must be installed first.
-   **System & Updates:** Access system-wide tasks, including the unified updater and driver manager.
-   **Check Installation Status:** Get a quick overview of what's installed and verify your system configuration.

## Updating Your Setup

To keep your toolkit and AI applications current, use the built-in update feature:
-   Navigate to `System & Updates` in the main menu.
-   Select **`Update Everything (Script & AI Stack)`**.

This smart updater works in two stages:
1.  It first checks for and pulls any updates for the toolkit scripts themselves. If updates are found, it will restart to apply them.
2.  It then proceeds to update your entire AI stack, including ROCm, PyTorch, and all the tools you've installed.

This ensures you're always using the latest, most stable update procedures.

## Advanced Topics

### GPU Compatibility

The script automatically detects the GPU architecture and sets the appropriate `HSA_OVERRIDE_GFX_VERSION` environment variable. This works for most modern AMD GPUs (RDNA 1/2/3, Vega, Polaris). The detection works even on a fresh system before ROCm is installed.

If you have a very new or unsupported GPU, you might need to set this variable manually. For the most accurate information, please consult the official AMD documentation.

-   **[Official Compatibility Matrix for ROCm (Latest Stable)](https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html)**

### A Note on APUs (Ryzen AI)

As of late 2025, ROCm support primarily targets discrete GPUs. While modern Ryzen APUs (like the 7040/8040 and AI 300 series) have powerful integrated graphics, their support in the ROCm ecosystem is still **highly experimental**.

This toolkit will attempt to detect APUs and apply experimental settings, but stability is not guaranteed. For the most stable and performant experience, an **officially supported discrete AMD Radeon GPU (RX 6000 series / RDNA2 or newer) is strongly recommended.**

The Neural Processing Unit (NPU) in "Ryzen AI" APUs is not used by this toolkit, as it is accessed via different software stacks and does not use ROCm.

## License

This project is open-source and available under the MIT License.
