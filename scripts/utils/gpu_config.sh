#!/bin/bash
# GPU configuration & auto-detection helper for ROCm WSL AI suite
# Provides: detect_and_export_rocm_env

GPU_ENV_FILE="$HOME/.config/rocm-wsl-ai/gpu.env"

_map_arch_to_hsa(){
  local arch="$1"
  case "$arch" in
    gfx12*) echo "12.0.0";;
    gfx11*) echo "11.0.0";;
    gfx103*) echo "10.3.0";;
    gfx101*) echo "10.1.0";;
    gfx90*) echo "9.0.0";;
    gfx803) echo "8.0.3";;
    *) echo "";;
  esac
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
  local arch=""; local hsa="";
  if command -v rocminfo >/dev/null 2>&1; then
    arch=$(rocminfo 2>/dev/null | grep -Eo 'gfx[0-9]+' | head -1 | tr -d '\r')
  fi
  if [ -z "$arch" ] && command -v clinfo >/dev/null 2>&1; then
    arch=$(clinfo 2>/dev/null | grep -Eo 'gfx[0-9]+' | head -1 | tr -d '\r')
  fi
  [ -z "$arch" ] && arch="gfx1100"  # fallback RDNA3 default
  hsa=$(_map_arch_to_hsa "$arch")
  local arch_list="gfx1200;gfx1201;gfx1100;gfx1101;gfx1102;gfx1030;gfx1010"
  export PYTORCH_ROCM_ARCH="$arch_list"
  [ -n "$hsa" ] && export HSA_OVERRIDE_GFX_VERSION="$hsa"
  mkdir -p "$(dirname "$GPU_ENV_FILE")"
  {
    echo "# Auto-generated GPU environment ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
    echo "# Detected arch: $arch"
    echo "export PYTORCH_ROCM_ARCH=\"$PYTORCH_ROCM_ARCH\""
    [ -n "$hsa" ] && echo "export HSA_OVERRIDE_GFX_VERSION=\"$hsa\""
  } >"$GPU_ENV_FILE.tmp" && mv "$GPU_ENV_FILE.tmp" "$GPU_ENV_FILE"
  success "GPU env written: $GPU_ENV_FILE (arch=$arch hsa=$hsa)"
}

export -f detect_and_export_rocm_env
