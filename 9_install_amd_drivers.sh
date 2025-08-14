#!/bin/bash

# AMD GPU Driver Installation Script for Ubuntu WSL2
# Installs and configures AMD GPU drivers for optimal ROCm and AI performance
# Version: 2025.1 - Compatible with ROCm 6.4.1

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Emoji for better visual feedback
SUCCESS="✅"
WARNING="⚠️"
ERROR="❌"
INFO="ℹ️"
ROCKET="🚀"

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  🔧 AMD GPU Driver Installation for ROCm & AI (2025)${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${YELLOW}▶ $1${NC}"
    echo "─────────────────────────────────────────────────────────────────"
}

print_info() {
    echo -e "${INFO} ${BLUE}$1${NC}"
}

print_success() {
    echo -e "${SUCCESS} ${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${WARNING} ${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${ERROR} ${RED}$1${NC}"
}

check_system() {
    print_section "System Check"
    
    # Check if running on Ubuntu
    if ! grep -q "Ubuntu" /etc/os-release; then
        print_error "This script is designed for Ubuntu. Current OS not supported."
        exit 1
    fi
    
    # Check Ubuntu version
    UBUNTU_VERSION=$(lsb_release -r | awk '{print $2}')
    print_info "Ubuntu version: $UBUNTU_VERSION"
    
    # Check if WSL2
    if grep -q microsoft /proc/version; then
        print_info "Running on WSL2"
        WSL_ENV=true
    else
        print_info "Running on native Ubuntu"
        WSL_ENV=false
    fi
    
    # Check architecture
    ARCH=$(uname -m)
    print_info "Architecture: $ARCH"
    
    if [ "$ARCH" != "x86_64" ]; then
        print_error "Only x86_64 architecture is supported"
        exit 1
    fi
}

check_existing_amdgpu_installation() {
    print_section "Checking Existing AMD GPU Installation"
    
    # Check for AMDGPU packages
    AMDGPU_INSTALLED=$(dpkg -l | grep -E "amdgpu|rocm" | grep -v "lib" | head -5)
    
    if [ -n "$AMDGPU_INSTALLED" ]; then
        print_warning "Existing AMD GPU/ROCm packages detected:"
        echo "$AMDGPU_INSTALLED"
        
        # Check for amdgpu-pro packages specifically
        AMDGPU_PRO=$(dpkg -l | grep "amdgpu-pro" || true)
        if [ -n "$AMDGPU_PRO" ]; then
            print_warning "AMDGPU-PRO packages detected - these need complete removal"
            NEEDS_REMOVAL=true
        fi
        
        # Check for old ROCm versions
        ROCM_VERSION_INSTALLED=$(dpkg -l | grep "rocm-dev" | awk '{print $3}' | head -1 || echo "")
        if [ -n "$ROCM_VERSION_INSTALLED" ]; then
            print_info "Current ROCm version: $ROCM_VERSION_INSTALLED"
            if [ "$ROCM_VERSION_INSTALLED" != "6.4.1" ]; then
                print_warning "Different ROCm version detected - update recommended"
                NEEDS_UPDATE=true
            fi
        fi
        
        return 0
    else
        print_info "No existing AMD GPU packages detected"
        return 1
    fi
}

remove_existing_amdgpu() {
    print_section "Removing Existing AMD GPU Drivers"
    
    print_warning "This will completely remove existing AMD GPU drivers and ROCm installation"
    print_warning "Your AI tools will be temporarily unavailable until reinstallation"
    
    read -p "Continue with removal? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Removal cancelled"
        return 1
    fi
    
    print_info "Stopping any running services..."
    sudo systemctl stop rocm-smi || true
    
    print_info "Removing AMDGPU-PRO packages..."
    sudo apt remove --purge -y amdgpu-pro* opencl-amdgpu-pro* vulkan-amdgpu-pro* 2>/dev/null || true
    
    print_info "Removing ROCm packages..."
    sudo apt remove --purge -y rocm-* hip-* miopen-* rocblas* rocsolver* rocfft* rocsparse* rccl* 2>/dev/null || true
    
    print_info "Removing AMDGPU kernel module packages..."
    sudo apt remove --purge -y amdgpu-dkms amdgpu-core 2>/dev/null || true
    
    print_info "Cleaning package cache..."
    sudo apt autoremove -y
    sudo apt autoclean
    
    # Remove repository files
    print_info "Removing repository configurations..."
    sudo rm -f /etc/apt/sources.list.d/rocm.list
    sudo rm -f /etc/apt/sources.list.d/amdgpu.list
    sudo rm -f /etc/apt/sources.list.d/amdgpu-proprietary.list
    
    # Remove apt keys
    print_info "Removing repository keys..."
    sudo apt-key del 0x9386B2A8 2>/dev/null || true  # AMD ROCm key
    
    # Update package lists
    sudo apt update
    
    print_success "Existing AMD GPU drivers removed successfully"
}

detect_amd_gpu() {
    print_section "AMD GPU Detection"
    
    # Detect AMD GPUs
    AMD_GPUS=$(lspci | grep -i "vga\|3d\|display" | grep -i "amd\|ati" || true)
    
    if [ -n "$AMD_GPUS" ]; then
        print_success "AMD GPU(s) detected:"
        echo "$AMD_GPUS" | while read -r line; do
            print_info "  $line"
        done
        
        # Detect specific GPU families
        if echo "$AMD_GPUS" | grep -qi "navi\|rdna\|rx 6\|rx 7\|rx 9"; then
            GPU_FAMILY="RDNA"
            print_info "RDNA GPU family detected"
        elif echo "$AMD_GPUS" | grep -qi "vega\|rx 5"; then
            GPU_FAMILY="VEGA"
            print_info "Vega GPU family detected"
        elif echo "$AMD_GPUS" | grep -qi "polaris\|rx 4\|rx 5"; then
            GPU_FAMILY="POLARIS"
            print_info "Polaris GPU family detected"
        else
            GPU_FAMILY="UNKNOWN"
            print_warning "Unknown GPU family detected"
        fi
    else
        print_warning "No AMD GPUs detected. Installation will continue for compatibility."
        GPU_FAMILY="NONE"
    fi
}

install_amd_drivers() {
    print_section "Installing AMD GPU Drivers"
    
    # Update system first
    print_info "Updating package lists..."
    sudo apt update
    
    # Install base graphics drivers
    print_info "Installing Mesa graphics drivers..."
    sudo apt install -y \
        mesa-utils \
        mesa-vulkan-drivers \
        vulkan-tools \
        mesa-opencl-icd \
        clinfo
    
    # Install firmware packages
    print_info "Installing AMD firmware..."
    sudo apt install -y \
        linux-firmware \
        firmware-amd-graphics
    
    # Install additional graphics libraries
    print_info "Installing additional graphics libraries..."
    sudo apt install -y \
        libgl1-mesa-dri \
        libglx-mesa0 \
        mesa-vdpau-drivers \
        mesa-va-drivers \
        vainfo \
        vdpauinfo
}

install_rocm_drivers() {
    print_section "Installing ROCm GPU Compute Drivers"
    
    # Add ROCm repository
    print_info "Adding ROCm repository..."
    wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | sudo apt-key add -
    
    # Add repository based on Ubuntu version
    if [[ "$UBUNTU_VERSION" == "24.04" ]]; then
        echo 'deb [arch=amd64] https://repo.radeon.com/rocm/apt/6.4.1/ jammy main' | sudo tee /etc/apt/sources.list.d/rocm.list
    elif [[ "$UBUNTU_VERSION" == "22.04" ]]; then
        echo 'deb [arch=amd64] https://repo.radeon.com/rocm/apt/6.4.1/ jammy main' | sudo tee /etc/apt/sources.list.d/rocm.list
    else
        echo 'deb [arch=amd64] https://repo.radeon.com/rocm/apt/6.4.1/ jammy main' | sudo tee /etc/apt/sources.list.d/rocm.list
    fi
    
    # Update package lists
    sudo apt update
    
    # Install ROCm packages
    print_info "Installing ROCm compute stack..."
    sudo apt install -y \
        rocm-dev \
        rocm-libs \
        rocm-utils \
        rocminfo \
        rocm-smi \
        hip-dev \
        hipcc
    
    # Install ROCm ML libraries
    print_info "Installing ROCm ML libraries..."
    sudo apt install -y \
        miopen-hip \
        rocblas \
        rocsolver \
        rocfft \
        rocsparse \
        rccl
}

configure_permissions() {
    print_section "Configuring User Permissions"
    
    # Add user to render group
    print_info "Adding user to render group..."
    sudo usermod -a -G render $USER
    
    # Add user to video group
    print_info "Adding user to video group..."
    sudo usermod -a -G video $USER
    
    # Create ROCm device rules
    print_info "Setting up device permissions..."
    echo 'SUBSYSTEM=="drm", KERNEL=="renderD*", GROUP="render", MODE="0666"' | sudo tee /etc/udev/rules.d/70-rocm.rules
    echo 'SUBSYSTEM=="kfd", KERNEL=="kfd", GROUP="render", MODE="0666"' | sudo tee -a /etc/udev/rules.d/70-rocm.rules
    
    # Reload udev rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
}

configure_environment() {
    print_section "Configuring Environment"
    
    # Add ROCm to PATH and LD_LIBRARY_PATH
    ROCM_ENV_FILE="$HOME/.rocm_env"
    
    print_info "Creating ROCm environment configuration..."
    cat > "$ROCM_ENV_FILE" << 'EOF'
# ROCm Environment Configuration
export ROCM_PATH=/opt/rocm
export PATH=$ROCM_PATH/bin:$ROCM_PATH/llvm/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH
export HIP_PATH=$ROCM_PATH
export ROCM_VERSION=6.4.1

# GPU Configuration
# Source auto-detected GPU environment if available (fallback keeps previous default)
[ -f "$HOME/.config/rocm-wsl-ai/gpu.env" ] && source "$HOME/.config/rocm-wsl-ai/gpu.env"
: "${HSA_OVERRIDE_GFX_VERSION:=11.0.0}"
export HCC_AMDGPU_TARGET=gfx1100,gfx1101,gfx1102,gfx1103
export HIP_VISIBLE_DEVICES=0

# ROCm ML Framework Configuration
export PYTORCH_ROCM_ARCH=gfx1100;gfx1101;gfx1102;gfx1103
export ROCM_HOME=/opt/rocm
EOF
    
    # Add to bashrc if not already present
    if ! grep -q "source.*\.rocm_env" "$HOME/.bashrc"; then
        print_info "Adding ROCm environment to ~/.bashrc..."
        echo "" >> "$HOME/.bashrc"
        echo "# ROCm Environment" >> "$HOME/.bashrc"
        echo "if [ -f ~/.rocm_env ]; then" >> "$HOME/.bashrc"
        echo "    source ~/.rocm_env" >> "$HOME/.bashrc"
        echo "fi" >> "$HOME/.bashrc"
    fi
    
    # Source the environment
    source "$ROCM_ENV_FILE"
}

test_installation() {
    print_section "Testing Installation"
    
    # Test graphics drivers
    print_info "Testing graphics drivers..."
    if command -v glxinfo &> /dev/null; then
        GRAPHICS_RENDERER=$(glxinfo | grep "OpenGL renderer" | head -1)
        if [[ "$GRAPHICS_RENDERER" == *"AMD"* ]] || [[ "$GRAPHICS_RENDERER" == *"Radeon"* ]]; then
            print_success "Graphics drivers working: $GRAPHICS_RENDERER"
        else
            print_warning "Graphics test: $GRAPHICS_RENDERER"
        fi
    fi
    
    # Test Vulkan
    print_info "Testing Vulkan support..."
    if command -v vulkaninfo &> /dev/null; then
        if vulkaninfo --summary | grep -q "AMD\|RADV"; then
            print_success "Vulkan AMD driver detected"
        else
            print_warning "Vulkan AMD driver not detected"
        fi
    fi
    
    # Test ROCm
    print_info "Testing ROCm installation..."
    source "$HOME/.rocm_env"
    
    if command -v rocminfo &> /dev/null; then
        if rocminfo | grep -q "Agent"; then
            print_success "ROCm compute stack working"
            rocminfo | grep "Marketing Name" | head -3
        else
            print_warning "ROCm compute stack may have issues"
        fi
    else
        print_error "ROCm tools not found"
    fi
    
    # Test ROCm SMI
    if command -v rocm-smi &> /dev/null; then
        print_info "ROCm SMI output:"
        rocm-smi --showproductname || print_warning "ROCm SMI not fully functional"
    fi
    
    # Test OpenCL
    if command -v clinfo &> /dev/null; then
        print_info "Testing OpenCL..."
        if clinfo | grep -q "AMD"; then
            print_success "OpenCL AMD support detected"
        else
            print_warning "OpenCL AMD support not detected"
        fi
    fi
}

main() {
    print_header
    
    # Check for existing installation first
    if check_existing_amdgpu_installation; then
        echo ""
        print_warning "Existing AMD GPU installation detected!"
        echo ""
        echo "Options:"
        echo "1) Update (Remove existing + Install latest) - Recommended"
        echo "2) Fresh Install (Remove existing + Clean install)"
        echo "3) Skip installation (Keep current version)"
        echo "4) Cancel"
        echo ""
        read -p "Choose option [1-4]: " -n 1 -r UPDATE_CHOICE
        echo
        
        case $UPDATE_CHOICE in
            1|2)
                print_info "Starting AMD GPU driver update/reinstallation..."
                if ! remove_existing_amdgpu; then
                    print_error "Failed to remove existing installation"
                    exit 1
                fi
                ;;
            3)
                print_info "Keeping existing installation"
                print_warning "Note: Some features may not work with older versions"
                exit 0
                ;;
            4)
                print_info "Installation cancelled"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                exit 1
                ;;
        esac
    else
        print_info "Starting fresh AMD GPU driver installation..."
        read -p "Continue with installation? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    check_system
    detect_amd_gpu
    # WSL GPU Support Check (only RDNA3/RDNA4 are exposed for compute in WSL currently)
    if [ "$WSL_ENV" = true ]; then
        case "$GPU_FAMILY" in
            RDNA)
                # Simple heuristic check for RDNA3/4 model naming
                if echo "$AMD_GPUS" | grep -qiE "RX 9|RX9| 9[0-9]{2}0|RX 7|7900|7800|7700|7600|RX7"; then
                    print_info "WSL note: Detected RDNA generation looks like RDNA3/4 – ROCm compute should be available."
                else
                    print_warning "WSL note: Detected RDNA generation does not look like RDNA3/4. AMD currently supports only RDNA3 & RDNA4 for GPU compute in WSL. GPU acceleration will likely NOT work."
                    read -p "Continue anyway (installation proceeds, likely CPU-only)? (y/N): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        print_info "Aborting due to unsupported GPU for WSL compute."
                        exit 0
                    fi
                fi
                ;;
            VEGA|POLARIS|UNKNOWN|NONE)
                print_warning "WSL note: Only RDNA3 & RDNA4 are supported for ROCm compute in WSL. Your GPU generation ($GPU_FAMILY) is not exposed. You can continue but you won't get GPU acceleration."
                read -p "Continue? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    print_info "Aborting due to unsupported GPU."
                    exit 0
                fi
                ;;
        esac
    fi
    install_amd_drivers
    install_rocm_drivers
    configure_permissions
    configure_environment
    test_installation
    
    print_section "Installation Complete"
    print_success "AMD GPU drivers installed successfully!"
    print_warning "Please restart your terminal or run: source ~/.bashrc"
    print_info "You may need to restart WSL2 for all changes to take effect"
    
    echo ""
    print_info "Next steps:"
    print_info "1. Restart your terminal session"
    print_info "2. Run: rocminfo to verify ROCm installation"
    print_info "3. Run: rocm-smi to check GPU status"
    if [ -n "$UPDATE_CHOICE" ] && [[ "$UPDATE_CHOICE" =~ ^[12]$ ]]; then
        print_info "4. Update your AI frameworks with: ./5_update_ai_setup.sh"
        print_warning "⚠️  Your AI tools may need to be updated/reconfigured after driver update"
    else
        print_info "4. Install AI frameworks with: ./1_setup_pytorch_rocm_wsl.sh"
    fi
    
    echo ""
    print_success "${ROCKET} Ready for AI development with AMD ROCm!"
}

# Run main function
main "$@"
