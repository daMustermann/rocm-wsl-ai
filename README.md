# AI Tools Setup for ROCm on Linux & WSL2

This repository provides a set of scripts to simplify the setup of a comprehensive AI environment using AMD GPUs with ROCm on both native Linux (Ubuntu) and WSL2. It includes a menu-driven interface to install, manage, and launch popular AI tools for image generation and large language models.

The scripts are designed to be idempotent and modular, ensuring a consistent and up-to-date installation by using the latest ROCm drivers and corresponding PyTorch nightly builds.

## Key Features

- **Cross-Platform:** Works on both native Ubuntu 22.04/24.04 and WSL2.
- **Automated GPU Detection:** Automatically detects your AMD GPU (RDNA1/2/3/4, Vega) and configures ROCm accordingly.
- **Always Up-to-Date:** Installs the latest ROCm stack from AMD's official repositories and fetches the compatible PyTorch nightly build.
- **Version Selection:** Allows choosing between the latest stable ROCm or experimental pre-releases (like ROCm 7.0 RC1).
- **Menu-Driven Interface:** A simple terminal UI (`menu.sh`) to guide you through installation, launching, and management of tools.
- **Comprehensive Tool Support:**
  - **Image Generation:** ComfyUI, Stable Diffusion WebUI (Automatic1111), SD.Next, InvokeAI, Fooocus, SD WebUI Forge.
- **Self-Contained:** Manages a dedicated Python virtual environment to avoid conflicts with system packages.
- **Utilities:** Includes scripts for system updates, status checks, and easy uninstallation of tools.

## Project Structure

The project is organized into the following directories:

- `scripts/`: Contains all the operational scripts.
  - `install/`: Scripts for installing various AI tools and dependencies.
  - `start/`: Scripts for launching the installed AI applications.
  - `utils/`: Helper scripts for updates, etc.

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/daMustermann/rocm-wsl-ai.git
    cd rocm-wsl-ai
    ```

2.  **Make scripts executable:**
    Run this command once to ensure all scripts have the necessary permissions.
    ```bash
    find . -name "*.sh" -exec chmod +x {} \;
    ```

3.  **Run the menu:**
    ```bash
    ./menu.sh
    ```

4.  **From the main menu, follow these steps:**
    -   Navigate to **"Install"** using the arrow keys and press Enter.
    -   Select **"ROCm & PyTorch Nightly (base)"** and press Enter. You will be prompted to choose a ROCm version. For most users, **"latest"** is the recommended, stable choice.
    -   The script will then:
        - Install the necessary AMD drivers and the selected ROCm stack.
        - Create a Python virtual environment (`~/genai_env`).
        - Install the latest PyTorch nightly build that matches the installed ROCm version, along with Triton.
    -   **Restart your system or WSL session** when prompted. This is crucial for user group permissions to take effect.
    -   Relaunch `./menu.sh` after restarting.

5.  **Install AI Tools:**
    -   Go back to the **"Install"** menu.
    -   Select any AI tool you wish to install (e.g., "ComfyUI", "Ollama"). The scripts will handle the download and setup within the correct environment.

## Updating from a Previous Version

If you have been using an older version of this repository with all scripts in the main folder, follow these steps to update to the new, structured version:

1.  **Save your local changes:** If you have made any modifications to the scripts, save them first to avoid conflicts:
    ```bash
    git stash
    ```

2.  **Pull the latest changes:** Fetch the new version from GitHub.
    ```bash
    git pull --rebase
    ```

3.  **Re-apply your changes (optional):** If you stashed changes in step 1, you can now re-apply them.
    ```bash
    git stash pop
    ```
    You might need to resolve some merge conflicts if your changes were made to files that have been moved.

4.  **Start using the new structure:** Your old script files have been moved into the `scripts/` directory. The new main entry point is `menu.sh`. Make sure it's executable (`chmod +x menu.sh`) and run it to continue.

## Usage

-   To start any installed tool, run `./menu.sh` and navigate to the **"Launch"** menu.
-   Always ensure you are running the tools from within the activated virtual environment. The launch scripts handle this automatically. If you need to run commands manually, first activate the environment:
    ```bash
    source ~/genai_env/bin/activate
    ```

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

## Updating

-   **To update the scripts themselves:** Use the **"Self-update (GitHub)"** option in the main menu.
-   **To update the entire AI stack** (ROCm, PyTorch, and installed tools): Use the **"Updates"** option in the main menu.

## License

This project is open-source and available under the MIT License.
