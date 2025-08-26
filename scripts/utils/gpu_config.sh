#!/bin/bash
# GPU configuration & auto-detection helper for ROCm WSL AI suite
# Provides: detect_and_export_rocm_env

GPU_ENV_FILE="$HOME/.config/rocm-wsl-ai/gpu.env"

# This function contains the complex pre-rocm-install GPU detection logic.
# It tries to identify the GPU using lspci (Linux) or pwsh (WSL).
# It returns a gfx string (e.g., "gfx1100") on success or an empty string on failure.
_detect_gpu_arch_pre_rocm() {
    local GPU_INFO=""
    local GFX_ARCH=""

    # Add error handling to prevent script exit on command failure
    set +e
    if is_wsl; then
        if command -v pwsh &> /dev/null; then
            GPU_INFO=$(pwsh -Command "Get-CimInstance -ClassName Win32_VideoController | Where-Object { \$_.Name -like '*Radeon*' -or \$_.Name -like '*AMD*' } | Select-Object -ExpandProperty Name" 2>/dev/null)
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

    # --- GPU Architecture Detection and Configuration ---
    # RDNA 3.5 (Strix Point / Strix Halo APUs, e.g., Ryzen AI 300 series)
    if [[ "$GPU_INFO" =~ 1150 || "$GPU_INFO" =~ 1151 ]] || [[ "$GPU_INFO" =~ "Ryzen AI 3" ]]; then
        if [[ "$GPU_INFO" =~ Halo || "$GPU_INFO" =~ HX[[:space:]]3[79] ]]; then GFX_ARCH="gfx1151";
        else GFX_ARCH="gfx1150"; fi
    # RDNA4 (Navi 4x, e.g., RX 9000 series) - Future-proofing
    elif [[ "$GPU_INFO" =~ 1200 || "$GPU_INFO" =~ 1201 ]] || [[ "$GPU_INFO" =~ RX[[:space:]]*9[0-9]{3} ]]; then
        if [[ "$GPU_INFO" =~ 99[0-9]{2} || "$GPU_INFO" =~ 1200 ]]; then GFX_ARCH="gfx1200";
        elif [[ "$GPU_INFO" =~ 98[0-9]{2} || "$GPU_INFO" =~ 97[0-9]{2} || "$GPU_INFO" =~ 1201 ]]; then GFX_ARCH="gfx1201";
        else GFX_ARCH="gfx1200"; fi
    # RDNA3 (Navi 3x, RX 7000 series & APUs)
    elif [[ "$GPU_INFO" =~ 1100 || "$GPU_INFO" =~ 1101 || "$GPU_INFO" =~ 1102 || "$GPU_INFO" =~ RX[[:space:]]*7[0-9]{3} || "$GPU_INFO" =~ 7[0-9]{3}M || "$GPU_INFO" =~ "Radeon 7" ]]; then
        if [[ "$GPU_INFO" =~ 79[0-9]{2} || "$GPU_INFO" =~ 1100 ]]; then GFX_ARCH="gfx1100";
        elif [[ "$GPU_INFO" =~ 78[0-9]{2} || "$GPU_INFO" =~ 77[0-9]{2} || "$GPU_INFO" =~ 1101 ]]; then GFX_ARCH="gfx1101";
        elif [[ "$GPU_INFO" =~ 76[0-9]{2} || "$GPU_INFO" =~ 7[0-9]{3}M || "$GPU_INFO" =~ 1102 ]]; then GFX_ARCH="gfx1102";
        else GFX_ARCH="gfx1100"; fi
    # RDNA2 (Navi 2x, RX 6000 series)
    elif [[ "$GPU_INFO" =~ 1030 || "$GPU_INFO" =~ 1031 || "$GPU_INFO" =~ 1032 || "$GPU_INFO" =~ 1034 ]] || [[ "$GPU_INFO" =~ RX[[:space:]]*6[0-9]{3} ]]; then
        if [[ "$GPU_INFO" =~ 69[0-9]{2} || "$GPU_INFO" =~ 68[0-9]{2} || "$GPU_INFO" =~ 1030 ]]; then GFX_ARCH="gfx1030";
        elif [[ "$GPU_INFO" =~ 67[0-9]{2} || "$GPU_INFO" =~ 1031 ]]; then GFX_ARCH="gfx1031";
        elif [[ "$GPU_INFO" =~ 66[0-9]{2} || "$GPU_INFO" =~ 1032 ]]; then GFX_ARCH="gfx1032";
        elif [[ "$GPU_INFO" =~ 65[0-9]{2} || "$GPU_INFO" =~ 64[0-9]{2} || "$GPU_INFO" =~ 1034 ]]; then GFX_ARCH="gfx1034";
        else GFX_ARCH="gfx1030"; fi
    # RDNA1 (Navi 1x, RX 5000 series)
    elif [[ "$GPU_INFO" =~ 1010 || "$GPU_INFO" =~ 1012 ]] || [[ "$GPU_INFO" =~ RX[[:space:]]*5[0-9]{3} ]]; then
        if [[ "$GPU_INFO" =~ 57[0-9]{2} || "$GPU_INFO" =~ 56[0-9]{2} || "$GPU_INFO" =~ 1010 ]]; then GFX_ARCH="gfx1010";
        elif [[ "$GPU_INFO" =~ 55[0-9]{2} || "$GPU_INFO" =~ 54[0-9]{2} || "$GPU_INFO" =~ 1012 ]]; then GFX_ARCH="gfx1012";
        else GFX_ARCH="gfx1010"; fi
    # Vega / GCN 5
    elif [[ "$GPU_INFO" =~ Vega || "$GPU_INFO" =~ Radeon[[:space:]]VII || "$GPU_INFO" =~ 90[0-9] ]]; then
        if [[ "$GPU_INFO" =~ Radeon[[:space:]]VII || "$GPU_INFO" =~ 906 ]]; then GFX_ARCH="gfx906";
        else GFX_ARCH="gfx900"; fi
    # Polaris / GCN 4 (RX 500/400 series)
    elif [[ "$GPU_INFO" =~ Polaris || "$GPU_INFO" =~ RX[[:space:]]*[54][0-9]{2} || "$GPU_INFO" =~ 803 ]]; then
        GFX_ARCH="gfx803";
    fi

    echo "$GFX_ARCH"
}

detect_and_export_rocm_env(){
  # If user has already set HSA_OVERRIDE_GFX_VERSION, respect it.
  if [ -n "${HSA_OVERRIDE_GFX_VERSION-}" ]; then
    local arch_list="gfx1200;gfx1201;gfx1100;gfx1101;gfx1102;gfx1030;gfx1010"
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

  local hsa_override_val="$arch"
  local arch_list="gfx1200;gfx1201;gfx1100;gfx1101;gfx1102;gfx1030;gfx1010"
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
