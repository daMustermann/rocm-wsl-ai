#!/bin/bash
# GPU configuration & auto-detection helper for ROCm WSL AI suite
# Provides: detect_and_export_rocm_env

GPU_ENV_FILE="$HOME/.config/rocm-wsl-ai/gpu.env"

# This function contains the pre-rocm-install GPU detection logic.
# It tries to identify the GPU using lspci (Linux) or pwsh (WSL).
# It will only return RDNA3+ families (gfx11xx / gfx12xx). For older families
# the function returns an empty string so the caller can detect unsupported HW
# and abort gracefully.
_detect_gpu_arch_pre_rocm() {
  local GPU_INFO=""
  local GFX_ARCH=""

  # Add error handling to prevent script exit on command failure
  set +e
  if is_wsl; then
    if command -v pwsh &> /dev/null; then
      # Match common name strings (Radeon, AMD, ATI) and also check PNPDeviceID for vendor 1002
      GPU_INFO=$(pwsh -Command "Get-CimInstance -ClassName Win32_VideoController | Where-Object { \$_.Name -like '*Radeon*' -or \$_.Name -like '*AMD*' -or \$_.Name -like '*ATI*' -or (\$_.PNPDeviceID -match 'VEN_1002') } | ForEach-Object { \"$($_.Name) $($_.PNPDeviceID)\" } | Select-Object -First 1" 2>/dev/null)
    else
      warn "pwsh command not found. Cannot detect GPU via PowerShell for pre-install detection."
    fi
  else
    if command -v lspci &> /dev/null; then
      GPU_INFO=$(lspci | grep -i 'vga\|3d\|display' | grep -i 'amd\|radeon\|ati')
    else
      warn "lspci command not found. Cannot detect GPU via lspci for pre-install detection."
    fi
  fi
  set -e

  if [ -z "$GPU_INFO" ]; then
    warn "Could not detect AMD GPU details before ROCm installation. Will rely on post-install detection or fallback."
    echo ""
    return
  fi

  log "Pre-ROCm GPU Info: $GPU_INFO"

  # Prefer matching RDNA4 / gfx12xx identifiers
  if [[ "$GPU_INFO" =~ 1200 ]] || [[ "$GPU_INFO" =~ 1201 ]] || [[ "$GPU_INFO" =~ RX[[:space:]]*9[0-9]{3} ]]; then
    GFX_ARCH="gfx1200"
    echo "$GFX_ARCH"
    return
  fi

  # Match RDNA3 / gfx11xx (RX 7000 series and APUs)
  if [[ "$GPU_INFO" =~ 1100 ]] || [[ "$GPU_INFO" =~ 1101 ]] || [[ "$GPU_INFO" =~ 1102 ]] || [[ "$GPU_INFO" =~ RX[[:space:]]*7[0-9]{3} ]] || [[ "$GPU_INFO" =~ 7[0-9]{3}M ]]; then
    GFX_ARCH="gfx1100"
    echo "$GFX_ARCH"
    return
  fi

  # If we reach here the detected GPU looks like an older family (gfx10xx, Vega, Polaris)
  warn "Detected GPU does not appear to be RDNA3 or newer (pre-RDNA3 hardware). This toolkit only supports RDNA3 (gfx11xx) and newer."
  echo ""
}

detect_and_export_rocm_env(){
  # If user has already set HSA_OVERRIDE_GFX_VERSION, respect it.
  if [ -n "${HSA_OVERRIDE_GFX_VERSION-}" ]; then
    # Validate user-provided override: must be RDNA3+ (gfx11xx or gfx12xx)
    local numeric_override
    numeric_override=${HSA_OVERRIDE_GFX_VERSION#gfx}
    if ! [[ "$numeric_override" =~ ^[0-9]+$ ]] || [ "$numeric_override" -lt 1100 ]; then
      print_error "Provided HSA_OVERRIDE_GFX_VERSION='$HSA_OVERRIDE_GFX_VERSION' is not RDNA3+ (gfx11xx/gfx12xx). Aborting."
      return 1
    fi

    local arch_list="gfx1200;gfx1201;gfx1100;gfx1101;gfx1102"
    export PYTORCH_ROCM_ARCH="$arch_list"

    mkdir -p "$(dirname "$GPU_ENV_FILE")"
    {
      echo "# Auto-generated GPU environment ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
      echo "# Using user-defined HSA_OVERRIDE_GFX_VERSION: $HSA_OVERRIDE_GFX_VERSION"
      echo "export PYTORCH_ROCM_ARCH=\"$PYTORCH_ROCM_ARCH\""
      echo "export HSA_OVERRIDE_GFX_VERSION=\"$HSA_OVERRIDE_GFX_VERSION\""
    } >"$GPU_ENV_FILE.tmp" && mv "$GPU_ENV_FILE.tmp" "$GPU_ENV_FILE"
    success "GPU env written: $GPU_ENV_FILE (using user-defined HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE_GFX_VERSION)"
    return 0
  fi

  # --- Auto-detection logic ---
  local arch=""
  # First, try post-install tools like rocminfo or clinfo
  if command -v rocminfo >/dev/null 2>&1; then
    arch=$(rocminfo 2>/dev/null | grep -Eo 'gfx[0-9]+' | head -1 | tr -d '\r')
  fi
  if [ -z "$arch" ] && command -v clinfo >/dev/null 2>&1; then
    arch=$(clinfo 2>/dev/null | grep -Eo 'gfx[0-9]+' | head -1 | tr -d '\r')
  fi

  # If post-install tools fail (e.g., fresh system), use pre-install detection
  if [ -z "$arch" ]; then
    log "rocminfo/clinfo not found. Attempting pre-install GPU detection..."
    arch=$(_detect_gpu_arch_pre_rocm)
    if [ -n "$arch" ]; then
      log "Detected GPU arch '$arch' using lspci/pwsh."
    fi
  else
      log "Detected GPU arch '$arch' using rocminfo/clinfo."
  fi

  # If all detection fails, fallback to a default
  if [ -z "$arch" ]; then
    arch="gfx1100"  # fallback RDNA3 default
    warn "Could not detect GPU architecture. Falling back to default: $arch"
  fi
  # Validate detected arch is RDNA3+; if a pre-install detection returned an older family,
  # abort so we don't attempt to install on unsupported hardware.
  local numeric_arch
  numeric_arch=${arch#gfx}
  if ! [[ "$numeric_arch" =~ ^[0-9]+$ ]] || [ "$numeric_arch" -lt 1100 ]; then
    print_error "Detected GPU architecture '$arch' is older than RDNA3. This toolkit only supports RDNA3 (gfx11xx) and newer. Aborting."
    return 1
  fi

  local hsa_override_val="$arch"
  local arch_list="gfx1200;gfx1201;gfx1100;gfx1101;gfx1102"
  export PYTORCH_ROCM_ARCH="$arch_list"
  export HSA_OVERRIDE_GFX_VERSION="$hsa_override_val"

  mkdir -p "$(dirname "$GPU_ENV_FILE")"
  {
    echo "# Auto-generated GPU environment ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
    echo "# Detected arch: $arch"
    echo "export PYTORCH_ROCM_ARCH=\"$PYTORCH_ROCM_ARCH\""
    echo "export HSA_OVERRIDE_GFX_VERSION=\"$hsa_override_val\""
  } >"$GPU_ENV_FILE.tmp" && mv "$GPU_ENV_FILE.tmp" "$GPU_ENV_FILE"
  success "GPU env written: $GPU_ENV_FILE (arch=$arch hsa=$hsa_override_val)"
}

export -f detect_and_export_rocm_env
