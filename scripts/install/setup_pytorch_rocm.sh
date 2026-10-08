#!/bin/bash
# ==============================================================================
# Base Environment Installer
#
# Installs the ROCm stack plus a working PyTorch, with everything resolved from
# AMD's repositories at run time by lib/version.sh. Nothing is pinned, so a new
# ROCm release becomes installable without editing this file.
#
# Two channels exist, selected with ROCM_AI_CHANNEL (or `upgrade.sh --target`):
#
#   core   (default)  ROCm 10.x. Built with AMD's "TheRock" system:
#                     packages are amdrocm10.1-gfx1100 from stable.repo.amd.com,
#                     installed under /opt/rocm/core-10.1. PyTorch is resolved by
#                     pip from AMD's index using a device extra rather than
#                     downloaded as named wheel files:
#                         pip install --index-url <index>/ \
#                             "rocm[libraries,device-gfx1100]==10.1.0" \
#                             "torch[device-gfx1100]"
#                     librocdxg, the WSL GPU bridge, SHIPS INSIDE ROCm here and
#                     is loaded automatically when /dev/dxg exists — there is no
#                     build step and no Windows SDK requirement.
#
#   legacy            ROCm 7.2.x. Packages are `rocm` from repo.radeon.com,
#                     PyTorch wheels are downloaded by filename, and librocdxg
#                     must be BUILT from source against the Windows SDK. Kept
#                     because WSL support in 10.x is still a technical preview.
#
# AMD's documentation:
# - ROCm install:   https://rocm.docs.amd.com/en/latest/install/rocm.html
# - TheRock builds: https://github.com/ROCm/TheRock/blob/main/RELEASES.md
# ==============================================================================
set -euo pipefail

SCRIPT_DIR_INSTALL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR_INSTALL/../../lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR_INSTALL/../../lib/common.sh"
else
    echo "common.sh not found, cannot proceed." >&2; exit 1
fi
# shellcheck disable=SC1091
source "$SCRIPT_DIR_INSTALL/../../lib/version.sh"

# Force pip to ignore global user-install flags, which break virtual environments.
export PIP_USER=0

VENV_NAME="genai_env"

if ! is_wsl; then
    err "This script is designed specifically for WSL2 environments."
    err "For native Linux installations, please refer to AMD's documentation."
    exit 1
fi

log "Running in Windows Subsystem for Linux (WSL2)"

# ==============================================================================
# Ubuntu and Python
# ==============================================================================
headline "TASK 1/7: Detecting Ubuntu and Python"

UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo unknown)
UBUNTU_CODENAME=$(va_ubuntu_codename)
log "Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"

# The interpreter must be one AMD publishes wheels for. The mapping is
# codename -> distribution default; ROCm 10.1 ships cp310 through cp314, so all
# three supported releases resolve without a mismatch.
case "$UBUNTU_CODENAME" in
    jammy)    PYTHON_VERSION="3.10" ;;
    noble)    PYTHON_VERSION="3.12" ;;
    resolute) PYTHON_VERSION="3.13" ;;
    *)
        err "Unsupported Ubuntu release: ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"
        err "ROCm 10.x is published for Ubuntu 22.04, 24.04 and 26.04."
        err "If your release genuinely is supported, set ROCM_AI_CHANNEL=legacy."
        exit 1
        ;;
esac
PYTHON_BIN="python${PYTHON_VERSION}"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || {
    err "$PYTHON_BIN not found. Install it with:  sudo apt install ${PYTHON_BIN} ${PYTHON_BIN}-venv"
    exit 1
}

# Confirm the interpreter is actually the version the codename implies, rather
# than something else that happens to share the name. A distro that has moved its
# default Python, or a user who installed a newer one over the top, would
# otherwise silently get wheels for the wrong ABI — and the failure would surface
# much later as an import error in torch.
ACTUAL_PY="$(va_python_version "$PYTHON_BIN" 2>/dev/null || true)"
if [ -n "$ACTUAL_PY" ] && [ "$ACTUAL_PY" != "$PYTHON_VERSION" ]; then
    warn "$PYTHON_BIN is Python ${ACTUAL_PY}, not the ${PYTHON_VERSION} this Ubuntu"
    warn "release normally ships. Using it anyway — AMD publishes wheels for it."
else
    success "Python ${ACTUAL_PY:-$PYTHON_VERSION}"
fi

WHEEL_SUFFIX="$(va_python_tag "$PYTHON_BIN" 2>/dev/null || true)"
[ -n "$WHEEL_SUFFIX" ] || {
    err "Could not determine the Python wheel tag for $PYTHON_BIN."
    exit 1
}
success "Wheel tag: ${WHEEL_SUFFIX}"

# ==============================================================================
# GPU architecture
# ==============================================================================
headline "TASK 2/7: Identifying your GPU"

# AMD publishes a per-architecture apt package, and PyTorch needs a matching
# device extra, so this one value decides what gets installed. Detection order
# is recorded choice -> existing ROCm -> AMD's own detector. When none of those
# can answer, the user is asked rather than the installer guessing: installing
# the wrong architecture package produces a machine with no working GPU and no
# obvious reason why.
GFX_TARGET=""
if GFX_TARGET="$(va_gfx_detect 2>/dev/null)" && [ -n "$GFX_TARGET" ]; then
    success "GPU architecture: gfx${GFX_TARGET}"
else
    warn "Could not detect your GPU architecture automatically."
    warn "AMD publishes one ROCm package per architecture, so this has to be right."
    warn "Run 'lspci | grep -i vga' in WSL, or check your card's model name against"
    warn "AMD's list: https://rocm.docs.amd.com/en/latest/reference/gpu-arch-specs.html"

    # The friendly table below is the first thing anyone looks for, but it is a
    # snapshot and it will rot. The authoritative list is read from AMD's own
    # package index, and printed underneath so a card that is newer than this
    # script still appears.
    printf '\n  Common Radeon / Ryzen targets:\n'
    printf '    gfx1100  RX 7900 XTX / 7900 XT / 7900 GRE / W7900 / W7800\n'
    printf '    gfx1101  RX 7800 XT / 7700 XT / 7700 / W7700\n'
    printf '    gfx1102  RX 7600\n'
    printf '    gfx1200  RX 9060 / 9060 XT\n'
    printf '    gfx1201  RX 9070 / 9070 XT / AI PRO R9700 / R9600\n'
    printf '    gfx1030  Radeon PRO W6800 / V620\n'

    local_targets="$(va_supported_gfx_targets 2>/dev/null | tr '\n' ' ')"
    if [ -n "$local_targets" ]; then
        printf '\n  Everything ROCm %s publishes (from AMD'"'"'s index):\n' \
            "$(va_latest_core_series)"
        printf '    %s\n' "$local_targets"
    fi

    printf '\n  Enter your target (blank for gfx1100): ' >&2
    read -r answer || answer=""
    GFX_TARGET="${answer:-1100}"
    GFX_TARGET="${GFX_TARGET#gfx}"
fi

case "$GFX_TARGET" in
    ''|*[!0-9a-z]*)
        err "That is not a valid target: '${GFX_TARGET}'"
        exit 1
        ;;
esac

# ==============================================================================
# Resolve versions from AMD
# ==============================================================================
headline "TASK 3/7: Resolving versions from AMD"

SPEC=""
if ! SPEC="$(va_resolve_torch_spec "$GFX_TARGET" "$WHEEL_SUFFIX")"; then
    err "Could not resolve a ROCm release with PyTorch wheels for ${WHEEL_SUFFIX}."
    err "Index: ${ROCM_AI_WHL_INDEX}"
    err "Check the index above in a browser, then re-run. If you are offline,"
    err "upgrade.sh --check reports the last known-good combination."
    exit 1
fi
eval "$SPEC"

success "ROCm ${ROCM_VERSION} (series ${ROCM_SERIES})"
success "PyTorch ${TORCH_VERSION} for ${PYTHON_TAG}"
success "Architecture package: ${APT_META_PACKAGE}"

# A legacy 7.2.x install cannot coexist with 10.x: AMD requires the old stack be
# removed first, and the two package trees both claim /opt/rocm.
LEGACY_PRESENT=no
[ "$(va_install_kind)" = "legacy" ] || [ "$(va_install_kind)" = "both" ] && LEGACY_PRESENT=yes

printf '\n'
if [ "$LEGACY_PRESENT" = "yes" ]; then
    warn "A legacy ROCm 7.2.x install is present ($(va_rocm_installed))."
    warn "ROCm 10.x cannot be installed alongside it — AMD requires the old stack"
    warn "to be removed, and both would claim /opt/rocm."
    warn ""
    warn "Use the upgrade path instead, which removes the old stack safely:"
    warn "    ./upgrade.sh --target core"
    exit 1
fi

log "This will install:"
log "  ROCm       ${ROCM_VERSION}  ->  /opt/rocm/core-${ROCM_SERIES}"
log "  Architecture ${GFX_TARGET}"
log "  PyTorch    ${TORCH_VERSION}"
log "  venv       ~/${VENV_NAME}"
printf '\n'

if [ "${ROCM_AI_ASSUME_YES:-0}" != "1" ] && ! confirm "Proceed with the installation?"; then
    log "Cancelled."
    exit 0
fi

# ==============================================================================
# Prerequisites
# ==============================================================================
headline "TASK 4/7: System prerequisites"
ensure_apt_packages wget curl gpg git "${PYTHON_BIN}" "${PYTHON_BIN}-venv" python3-pip ca-certificates
success "Prerequisites installed."

# ==============================================================================
# ROCm from AMD's signed apt repository
# ==============================================================================
headline "TASK 5/7: Installing ROCm ${ROCM_VERSION} (${GFX_TARGET})"

KEYRING="/etc/apt/keyrings/amdrocm.gpg"
log "Installing AMD's repository signing key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL "$ROCM_AI_AMD_GPG_KEY" | gpg --dearmor | sudo tee "$KEYRING" >/dev/null || {
    err "Failed to install the ROCm signing key from ${ROCM_AI_AMD_GPG_KEY}"
    err "Check your internet connection."
    exit 1
}
success "Signing key installed at ${KEYRING}"

# Replace rather than accumulate: a stale amdrocm-stable.sources pointing at a
# different series is the usual cause of "no candidate version".
log "Writing the ROCm apt source..."
va_core_apt_source | sudo tee /etc/apt/sources.list.d/amdrocm-stable.sources >/dev/null || {
    err "Could not write /etc/apt/sources.list.d/amdrocm-stable.sources"
    exit 1
}

log "Refreshing package lists..."
sudo apt-get update -y >/dev/null 2>&1 || {
    err "apt-get update failed. The ROCm repository may be unreachable."
    exit 1
}

# Install only the architecture package for this GPU rather than every
# supported one: it is a fraction of the size and avoids pulling kernels for
# hardware that is not present.
PER_ARCH_PACKAGE="$(va_core_meta_package "$ROCM_SERIES" "$GFX_TARGET")"
log "Installing ${PER_ARCH_PACKAGE} (several GB; this takes a while)..."
if ! sudo apt-get install -y "$PER_ARCH_PACKAGE"; then
    err "ROCm installation failed. The error above says which package was missing."
    err "Confirm ${PER_ARCH_PACKAGE} exists for your Ubuntu release at:"
    err "    $(va_core_apt_base)/"
    exit 1
fi

success "ROCm installed. Version reported: $(va_rocm_installed 2>/dev/null || echo unknown)"

# ==============================================================================
# The WSL GPU bridge
# ==============================================================================
headline "TASK 6/7: Verifying the WSL GPU bridge"

# ROCr loads librocdxg automatically when it finds /dev/dxg, so there is nothing
# to build or install here — the check is only to confirm the pieces are present
# so a failure later is diagnosable.
if [ ! -c /dev/dxg ]; then
    err "/dev/dxg is missing: WSL2 cannot reach the GPU at all."
    err "  From PowerShell run:  wsl --shutdown"
    err "  Then reopen WSL and re-run this installer."
    exit 1
fi
success "WSL GPU device /dev/dxg is present"

if has_rocdxg; then
    success "librocdxg present (shipped with ROCm ${ROCM_VERSION})"
else
    warn "librocdxg not found in the ROCm tree."
    warn "ROCm 10.1 normally ships it. If the GPU stays invisible, check:"
    warn "    find /opt/rocm -name 'librocdxg*' 2>/dev/null"
fi

log "Adding current user ($USER) to the 'render' and 'video' groups..."
sudo usermod -a -G render,video "$LOGNAME" 2>/dev/null || true

# ==============================================================================
# Virtual environment and PyTorch
# ==============================================================================
headline "TASK 7/7: Installing PyTorch ${TORCH_VERSION}"

if [ ! -d "$HOME/$VENV_NAME" ]; then
    "$PYTHON_BIN" -m venv "$HOME/$VENV_NAME"
    log "Created virtual environment at ~/${VENV_NAME}"
else
    warn "~/${VENV_NAME} already exists; reusing it."
    warn "  Delete it by hand if the install misbehaves."
fi

# shellcheck disable=SC1091
source "$HOME/$VENV_NAME/bin/activate"

pip install --quiet --upgrade pip wheel

# Remove any previous PyTorch before installing the ROCm build. Leaving a CUDA
# torch in place is the single most common cause of "torch works but the GPU is
# not visible".
pip uninstall -y torch torchvision torchaudio triton triton-kernels 2>/dev/null || true

log "Installing from ${PIP_INDEX}"
log "  ${PIP_SPEC_ROCM}"
log "  ${PIP_SPEC_TORCH}"
log "  ${PIP_SPEC_TORCHVISION}"
log "  ${PIP_SPEC_TORCHAUDIO}"
printf '\n'

# pip resolves the device extras itself, including the amd-torch-device-* wheels
# that carry the GPU-specific kernels. No wheel is downloaded by hand.
if ! pip install --index-url "$PIP_INDEX" \
        "$PIP_SPEC_ROCM" \
        "$PIP_SPEC_TORCH" \
        "$PIP_SPEC_TORCHVISION" \
        "$PIP_SPEC_TORCHAUDIO"; then
    err "PyTorch installation failed."
    err "Most often this means the device extra does not exist for this GPU."
    err "Try:  pip install --index-url ${PIP_INDEX} 'torch[device-all]'"
    exit 1
fi

pip install --quiet sageattention 2>/dev/null \
    || warn "SageAttention not installed (optional)."

# The HSA runtime shipped inside torch's own lib directory conflicts with the one
# ROCm provides, and on a 7.2.x stack it was the cause of a hard crash. Whether
# it is still needed is measured rather than assumed: only if the GPU is
# invisible AND the bundled library exists.
maybe_fix_bundled_hsa_runtime() {
    local location lib
    location="$(pip show torch 2>/dev/null | awk -F': ' '/^Location:/{print $2}')"
    [ -n "$location" ] || return 0
    lib="$location/torch/lib"
    [ -d "$lib" ] || return 0

    if "$HOME/$VENV_NAME/bin/python" -c 'import torch,sys; sys.exit(0 if torch.cuda.is_available() else 1)' 2>/dev/null; then
        success "GPU already visible; leaving torch's bundled libraries untouched."
        return 0
    fi

    if ls "$lib"/libhsa-runtime64.so* >/dev/null 2>&1; then
        warn "GPU is not visible and torch bundles its own HSA runtime."
        warn "Removing the bundled copy so the ROCm-provided one is used..."
        rm -f "$lib"/libhsa-runtime64.so*
        if "$HOME/$VENV_NAME/bin/python" -c 'import torch,sys; sys.exit(0 if torch.cuda.is_available() else 1)' 2>/dev/null; then
            success "Removing the bundled HSA runtime fixed it."
        else
            warn "Still not visible. See docs/TROUBLESHOOTING.md"
        fi
    else
        warn "GPU is not visible and torch bundles no HSA runtime."
        warn "See docs/TROUBLESHOOTING.md -> 'PyTorch can't see my GPU'"
    fi
}
maybe_fix_bundled_hsa_runtime

# A minimal, honest activation script. The real GPU environment is applied by
# lib/launch.sh before Python starts; these two lines are only for people who
# activate the venv by hand.
#
# HSA_OVERRIDE_GFX_VERSION is deliberately never written here. Under WSL it makes
# the runtime reject the device, so PyTorch sees no GPU while rocminfo still
# lists one.
VENV_ACTIVATE="$HOME/$VENV_NAME/bin/activate"
grep -q "HSA_ENABLE_DXG_DETECTION" "$VENV_ACTIVATE" 2>/dev/null \
    || echo 'export HSA_ENABLE_DXG_DETECTION=1' >> "$VENV_ACTIVATE"
grep -q "PIP_USER=0" "$VENV_ACTIVATE" 2>/dev/null \
    || echo 'export PIP_USER=0' >> "$VENV_ACTIVATE"

# Record the architecture so a later rebuild installs the same packages.
_update_user_env "AMDROCM_DEVICE_TARGET" "gfx${GFX_TARGET}"

log "Installing the GPU environment for login shells..."
if rocm_ai_install_shell_integration; then
    success "GPU environment installed for new login shells."
else
    warn "Could not install the login-shell environment automatically."
    warn "See docs/TROUBLESHOOTING.md"
fi

# ==============================================================================
# Verification
# ==============================================================================
headline "Verification"

export HSA_ENABLE_DXG_DETECTION=1

log "rocminfo ..."
if command -v rocminfo >/dev/null 2>&1; then
    rocminfo 2>/dev/null | grep -E '^\s+(Name|Marketing Name):' | head -6 || warn "rocminfo listed no agents"
else
    warn "rocminfo not found; the ROCm install may be incomplete."
fi

# amd-smi gained WSL2 telemetry in ROCm 10.1, which WSL could not report before.
# Worth showing if present, purely informational.
if command -v amd-smi >/dev/null 2>&1; then
    log "amd-smi (ROCm 10.1 reports WSL telemetry through this) ..."
    amd-smi static 2>/dev/null | grep -iE 'gfx|product|vbios' | head -4 || true
fi

log "PyTorch ..."
"$HOME/$VENV_NAME/bin/python" - <<'PYEOF' || warn "The verification snippet itself failed."
import os
import torch

print(f"  PyTorch            {torch.__version__}")
print(f"  Built with HIP     {torch.version.hip or 'NO'}")
print(f"  GPU available      {torch.cuda.is_available()}")
print(f"  HSA_DXG_DETECTION  {os.environ.get('HSA_ENABLE_DXG_DETECTION', 'not set')}")
print(f"  HSA_OVERRIDE_GFX   {os.environ.get('HSA_OVERRIDE_GFX_VERSION', 'not set')}")
if torch.cuda.is_available():
    print(f"  Device count       {torch.cuda.device_count()}")
    print(f"  Device 0           {torch.cuda.get_device_name(0)}")
else:
    print("  [WARN] PyTorch does not see a GPU.")
    print("         If you have just installed, run 'wsl --shutdown' first.")
    print("         Then:  ~/genai_env/bin/python scripts/utils/gpu_diag.sh 2>/dev/null || bash scripts/utils/gpu_diag.sh")
PYEOF

printf '\n'
success "Base environment installed: ROCm ${ROCM_VERSION} + PyTorch ${TORCH_VERSION}"
printf '\n'
warn "Restart WSL so the group change takes effect:"
warn "  1. Close this terminal"
warn "  2. In PowerShell:  wsl --shutdown"
warn "  3. Reopen Ubuntu"
printf '\n'
log "Next: run ./menu.sh and install a tool, or ./scripts/utils/auto_tuner.sh to tune."