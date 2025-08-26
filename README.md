# AI Tools Setup for ROCm on Linux & WSL2

This repository provides a set of scripts to simplify the setup of a comprehensive AI environment using AMD GPUs with ROCm on both native Linux (Ubuntu) and WSL2. It includes a menu-driven interface to install, manage, and launch popular AI tools for image generation and large language models.

The scripts are designed to be idempotent and modular, ensuring a consistent and up-to-date installation by using the latest ROCm drivers and corresponding PyTorch nightly builds.

## Key Features

- **Cross-Platform:** Works on both native Ubuntu 22.04/24.04 and WSL2.
- **Automated GPU Detection:** Automatically detects your AMD GPU (RDNA1/2/3/4, Vega) and configures ROCm accordingly.
- **Always Up-to-Date:** Installs the latest ROCm stack from AMD's official repositories and fetches the compatible PyTorch nightly build.
- **Version Selection:** Allows choosing between the latest stable ROCm or experimental pre-releases (like ROCm 7.0 RC1).
- **Menu-Driven Interface:** A simple, intuitive terminal UI (`menu.sh`) guides you through every step.
- **Comprehensive Tool Support:**
  - **Image Generation:** ComfyUI, Stable Diffusion WebUI (Automatic1111), SD.Next, InvokeAI, Fooocus, SD WebUI Forge.
  - **Language Models:** Ollama.
- **Self-Contained:** Manages a dedicated Python virtual environment (`~/genai_env`) to avoid conflicts with system packages.
- **System Management:** Includes options for updating the entire stack, the scripts themselves, managing drivers, and checking the status of all components.

## Project Structure

The project is organized into the following directories:

- `scripts/`: Contains all the operational scripts.
  - `install/`: Scripts for installing various AI tools and dependencies.
  - `start/`: Scripts for launching the installed AI applications.
  - `utils/`: Helper scripts for updates, etc.

## Installation

The process is designed to be as simple as possible.

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/daMustermann/rocm-wsl-ai.git
    cd rocm-wsl-ai
    ```

2.  **Run the menu:**
    ```bash
    ./menu.sh
    ```
    The script will automatically ensure all necessary helper scripts are executable.

3.  **Perform the Base Installation:**
    This is the most important first step.
    -   From the main menu, navigate to `Manage Tools`.
    -   Select `Install a new tool`.
    -   Choose **`Base Installation (ROCm & PyTorch)`**.
    -   You will be prompted to select a ROCm version. For most users, **"latest"** is the recommended, stable choice.
    -   The script will then install the required AMD drivers, the full ROCm stack, and create the Python virtual environment with PyTorch and Triton.
    -   **Restart your system or WSL session** when the script completes. This is crucial for system changes to take effect.

4.  **Install AI Tools:**
    -   After restarting, run `./menu.sh` again.
    -   Navigate back to `Manage Tools` -> `Install a new tool`.
    -   Select any AI tool you wish to install (e.g., "ComfyUI", "Ollama"). The scripts will handle the download and setup automatically.

## Usage

-   To start any installed application, run `./menu.sh` and select `Launch an AI tool`.
-   To check what is installed, use the `Check Installation Status` option in the main menu.
-   The launch scripts handle activating the Python virtual environment automatically. If you need to run commands manually, first activate it with:
    ```bash
    source ~/genai_env/bin/activate
    ```

## System Management & Updates

The `System & Updates` menu provides access to core system tasks:

-   **Update Everything (Script & AI Stack):** This is the recommended way to keep your entire setup up-to-date. This smart update process works in two stages:
    1.  First, it checks for updates to the menu script itself from GitHub. If an update is found, it is downloaded and the script will restart.
    2.  After the script is confirmed to be up-to-date (or after it has just been updated and restarted), it will then ask if you want to proceed with updating the full AI Stack (ROCm, PyTorch, and all installed tools).
    This ensures you are always running the latest update logic before updating the rest of your environment.

-   **Manage AMD GPU Drivers:** This provides direct access to the driver installation script, which can also be used for repair or re-installation.

## ROCm Version Selection

This tool now allows you to choose which version of the ROCm stack to install:

-   **Latest Stable:** This is the default and recommended option. It installs the most recent, officially supported ROCm version, offering the best stability.
-   **ROCm 7.0 RC1 (Experimental):** This option installs a pre-release version of ROCm 7.0. It should only be used by advanced users who need access to the very latest features or hardware support and are comfortable with potential instability, bugs, or breaking changes.

## GPU Compatibility

Hardware support for ROCm is continuously updated by AMD. As the compatibility lists change frequently, especially for pre-release versions, the tables have been removed from this README to avoid providing outdated information.

I strongly recommend consulting the official AMD documentation to check the most current support status for your specific GPU and the desired ROCm version:

-   **[Official Compatibility Matrix for ROCm (Latest Stable Version)](https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html)**
-   **[Release Notes for ROCm 7.0 Pre-Releases (for experimental support)](https://rocm.docs.amd.com/en/docs-7.0-rc1/preview/release.html)**

These sources provide the most accurate and up-to-date information.

## For Users of Previous Versions

If you were using this repository before the menu structure was updated (before August 2025), please note that the script names and locations have changed. Your old `*.sh` files in the root directory are now organized inside the `scripts/` folder and are called by the main `menu.sh` script. It is recommended to do a fresh clone, but if you are updating via `git pull`, be aware of these changes.

## Ryzen AI APUs and ROCm Support

As of late 2025, the official ROCm support primarily targets AMD's discrete and datacenter GPUs. While modern Ryzen APUs contain powerful integrated graphics (iGPUs), their support within the ROCm ecosystem for general-purpose compute and AI is still evolving.

-   **Ryzen AI 300 Series (Strix Point, RDNA 3.5):**
    -   This latest generation, including models like the **Ryzen AI 9 HX 370**, features the new RDNA 3.5 graphics architecture (`gfx1150`/`gfx1151`).
    -   ROCm support for these APUs is under active development, as indicated by recent code commits in the ROCm repositories.
    -   However, this support is **highly experimental**. It is not yet officially validated by AMD. While these scripts will attempt to set the correct `HSA_OVERRIDE_GFX_VERSION`, stability and performance are not guaranteed. Users may encounter issues that require manual intervention. **WSL2 support for RDNA 3.5 is particularly unstable and not recommended at this time.**

-   **Older APUs (Ryzen 7040/8040 Series, RDNA 3):**
    -   These APUs have better-established, albeit still unofficial, support within the community. Many users have success running ROCm, but it often requires specific configurations.

-   **NPU (Ryzen AI Engine):**
    -   The Neural Processing Unit (NPU) present in "Ryzen AI" enabled APUs is a separate hardware block from the iGPU. It is designed for low-power AI inference and is accessed through different software stacks (like Microsoft's DirectML with ONNX Runtime), **not ROCm**. The scripts in this repository focus exclusively on GPU acceleration via ROCm.

-   **Recommendation:**
    -   For a stable and performant AI experience with this script suite, an **officially supported discrete AMD Radeon GPU (RX 6000 series / RDNA2 or newer) is strongly recommended.**
    -   **For WSL2, official support is limited to RDNA3, and newer discrete GPUs.** Using older architectures or experimental APUs on WSL2 may lead to significant issues.
    -   Using these scripts with any APU's integrated graphics should be considered experimental.

The landscape is changing quickly. For the latest information, always refer to the official [AMD ROCm Documentation](https://rocm.docs.amd.com/) and the [Radeon on WSL guide](https://rocm.docs.amd.com/projects/radeon/en/latest/docs/install/wsl/install-radeon.html).

## License

This project is open-source and available under the MIT License.
