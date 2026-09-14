#!/bin/bash
# GPU & ROCm Diagnostics — Comprehensive health check
# Sourced by menu.sh (defines run_gpu_diag) and runnable standalone.

SCRIPT_DIR_DIAG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "$SCRIPT_DIR_DIAG/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR_DIAG/lib/common.sh"
else
    echo "common.sh not found at $SCRIPT_DIR_DIAG/lib/common.sh" >&2; exit 1
fi

# Load user settings so HSA_OVERRIDE_GFX_VERSION etc. are in scope
load_user_env 2>/dev/null || true

# ──────────────────────────────────────────────────────────────────────────────
# _diag_row  LABEL  STATUS  DETAIL
#   STATUS one of: ok | warn | fail | info
# ──────────────────────────────────────────────────────────────────────────────
_diag_row() {
    local label="$1" status="$2" detail="$3"
    local color icon
    case "$status" in
        ok)   color=46;  icon="✔" ;;
        warn) color=214; icon="⚠" ;;
        fail) color=196; icon="✖" ;;
        *)    color=117; icon="ℹ" ;;  # info
    esac
    if command -v gum >/dev/null 2>&1; then
        printf "  %s  %-40s  %s\n" \
            "$(gum style --foreground "$color" "$icon")" \
            "$(gum style --foreground 252 "$label")" \
            "$(gum style --foreground "$color" "$detail")"
    else
        local icon_plain
        case "$status" in
            ok)   icon_plain="[ OK  ]" ;;
            warn) icon_plain="[ WARN]" ;;
            fail) icon_plain="[ FAIL]" ;;
            *)    icon_plain="[ INFO]" ;;
        esac
        printf "  %s  %-40s  %s\n" "$icon_plain" "$label" "$detail"
    fi
}

_diag_section() {
    echo ""
    if command -v gum >/dev/null 2>&1; then
        gum style --bold --foreground 63 --margin "0 1" "▸ $*"
    else
        printf "  ─── %s ───\n" "$*"
    fi
}

run_gpu_diag() {
    clear
    echo ""
    if command -v gum >/dev/null 2>&1; then
        gum style --bold --foreground 212 --border normal --border-foreground 212 \
            --padding "0 2" "🔍 GPU & ROCm Diagnostics — ROCm WSL AI Toolkit"
    else
        echo "=== GPU & ROCm Diagnostics ==="
    fi

    # ── Environment ──────────────────────────────────────────────────────────
    _diag_section "Environment"

    if is_wsl; then
        local wsl_distro="${WSL_DISTRO_NAME:-unknown}"
        _diag_row "WSL2 Environment"          ok   "Detected — distro: $wsl_distro"
    else
        _diag_row "WSL2 Environment"          warn "Native Linux (toolkit targets WSL2)"
    fi

    # ── ROCm Stack ───────────────────────────────────────────────────────────
    _diag_section "ROCm Stack"

    if command -v rocminfo >/dev/null 2>&1; then
        local rocm_ver="?"
        [ -f "/opt/rocm/.info/version" ] && \
            rocm_ver=$(cat /opt/rocm/.info/version 2>/dev/null | head -1 | tr -d '\r\n ')
        _diag_row "ROCm Installation"         ok   "Installed — v${rocm_ver}"
    else
        _diag_row "ROCm Installation"         fail "Not found → Install Tools → Base Environment"
    fi

    if has_rocdxg; then
        _diag_row "ROCDXG (librocdxg)"        ok   "/opt/rocm/lib/librocdxg.so ✓"
        # Check the .so actually links without missing symbols
        local ldd_out
        ldd_out=$(ldd /opt/rocm/lib/librocdxg.so 2>&1)
        if echo "$ldd_out" | grep -q "not found"; then
            local missing
            missing=$(echo "$ldd_out" | grep "not found" | awk '{print $1}' | tr '\n' ' ')
            _diag_row "ROCDXG link check"     fail "Missing libraries: $missing — rebuild ROCDXG"
        else
            _diag_row "ROCDXG link check"     ok   "All shared libraries resolved ✓"
        fi
    else
        _diag_row "ROCDXG (librocdxg)"        fail "Missing — GPU compute unavailable in WSL2"
    fi

    # /dev/dxg is the DXCore bridge device — without it ROCm cannot see the GPU
    if [ -e "/dev/dxg" ]; then
        _diag_row "/dev/dxg (DXCore bridge)"  ok   "Present ✓"
    else
        _diag_row "/dev/dxg (DXCore bridge)"  fail "Missing — Windows driver not exposing DXCore to WSL"
        _diag_row "  Fix"                     warn "Update AMD Adrenalin driver on Windows (26.2.2+)"
        _diag_row "  Fix"                     warn "Run in PowerShell: wsl --update  then wsl --shutdown"
    fi

    # User must be in render + video groups to access /dev/dxg
    local missing_groups=""
    id -nG 2>/dev/null | grep -qw "render" || missing_groups="${missing_groups}render "
    id -nG 2>/dev/null | grep -qw "video"  || missing_groups="${missing_groups}video"
    if [ -z "$missing_groups" ]; then
        _diag_row "User groups (render/video)" ok  "$(id -nG | tr ' ' ',')"
    else
        _diag_row "User groups (render/video)" fail "Missing: ${missing_groups% } — run: sudo usermod -a -G render,video \$USER  then wsl --shutdown"
    fi

    # ── Environment Variables ────────────────────────────────────────────────
    _diag_section "Environment Variables"

    local dxg_val="${HSA_ENABLE_DXG_DETECTION:-0}"
    if [ "$dxg_val" = "1" ]; then
        _diag_row "HSA_ENABLE_DXG_DETECTION"  ok   "=1 ✓"
    else
        _diag_row "HSA_ENABLE_DXG_DETECTION"  fail "Not set — GPU compute disabled in WSL2"
    fi

    local gfx_val="${HSA_OVERRIDE_GFX_VERSION:-}"
    if [ -n "$gfx_val" ]; then
        _diag_row "HSA_OVERRIDE_GFX_VERSION"  ok   "=\"$gfx_val\" (manual override)"
    else
        # Not set is only a problem when PyTorch/ROCm can't auto-detect the arch
        _diag_row "HSA_OVERRIDE_GFX_VERSION"  warn "Not set — if PyTorch can't see GPU, set this!"
        _diag_row "  RX 7900 XTX/XT"          info "Settings → GPU Profile  or: export HSA_OVERRIDE_GFX_VERSION=11.0.0"
        _diag_row "  RX 7800/7700 XT"         info "export HSA_OVERRIDE_GFX_VERSION=11.0.2"
        _diag_row "  RX 9070 / 9070 XT"       info "export HSA_OVERRIDE_GFX_VERSION=12.0.0"
    fi

    local dev_val="${ROCR_VISIBLE_DEVICES:-}"
    if [ -n "$dev_val" ]; then
        _diag_row "ROCR_VISIBLE_DEVICES"      ok   "=\"$dev_val\""
    else
        _diag_row "ROCR_VISIBLE_DEVICES"      info "Not set — all GPU agents visible"
    fi

    # ── GPU Detection via rocminfo ───────────────────────────────────────────
    _diag_section "GPU Detection (rocminfo)"

    # gpu_found is set at function scope so the summary block can read it
    local gpu_found=false

    if command -v rocminfo >/dev/null 2>&1; then
        export HSA_ENABLE_DXG_DETECTION=1
        local rocm_out
        # Capture stdout + stderr: some HSA/DXG messages arrive on stderr
        # and must not be discarded so the awk parser sees all agent data.
        rocm_out=$(rocminfo 2>&1 | tr -d '\r') || rocm_out=""

        # Extract GPU agents — accept entries with UUID even if Marketing Name / gfx arch
        # are missing (DXCore/WSL agents often omit those fields).
        local gpu_count=0
        while IFS='|' read -r mkt gfx uuid; do
            local label="${mkt:-Unknown GPU}"
            [ -n "$gfx"  ] && label="$label ($gfx)"
            [ -n "$uuid" ] && label="$label [${uuid}]"
            _diag_row "GPU $gpu_count detected"   ok   "$label"
            ((gpu_count++)) || true
        done < <(echo "$rocm_out" | awk '
            /^Agent [0-9]+/ {
                if (is_gpu) printf "%s|%s|%s\n", mkt, gfx, uuid
                is_gpu=0; mkt=""; gfx=""; uuid=""
            }
            /Device Type:.*GPU/ { is_gpu=1 }
            /Marketing Name:/ {
                sub(/.*Marketing Name:[[:space:]]*/, "")
                sub(/[[:space:]]*$/, "")
                mkt=$0
            }
            /^[[:space:]]+Name:[[:space:]]+gfx[0-9]+/ {
                match($0, /gfx[0-9]+/)
                gfx=substr($0, RSTART, RLENGTH)
            }
            /Uuid:/ {
                sub(/.*Uuid:[[:space:]]*/, "")
                sub(/[[:space:]]*$/, "")
                uuid=$0
            }
            END { if (is_gpu) printf "%s|%s|%s\n", mkt, gfx, uuid }
        ' | grep -v "^||$")   # skip empty lines (CPU-only output)

        if [ "$gpu_count" -gt 0 ]; then
            gpu_found=true
        else
            _diag_row "GPU Detection"             fail "No AMD GPU found by rocminfo"
            if is_wsl; then
                _diag_row "  Most likely fix"      warn "Run in PowerShell: wsl --shutdown  then restart Ubuntu"
                _diag_row "  Check driver"         info "Requires AMD Adrenalin 26.2.2+ on Windows"
                _diag_row "  WSL kernel"           info "Run in PowerShell: wsl --update"
                _diag_row "  DXG bridge"           info "Ensure HSA_ENABLE_DXG_DETECTION=1 (already set here)"
            fi
        fi
    else
        _diag_row "GPU Detection"                 info "rocminfo not available (ROCm not installed)"
    fi

    # ── Python / PyTorch ─────────────────────────────────────────────────────
    _diag_section "Python & PyTorch"

    local genai_venv="$HOME/genai_env"
    if [ -f "$genai_venv/bin/activate" ]; then
        _diag_row "genai_env (inference venv)" ok   "$genai_venv"

        local pt_result
        pt_result=$(
            # shellcheck disable=SC1090
            source "$genai_venv/bin/activate" 2>/dev/null
            HSA_ENABLE_DXG_DETECTION=1 \
            python3 -c "
import torch, sys
ver = torch.__version__
avail = torch.cuda.is_available()
gpu = torch.cuda.get_device_name(0) if avail else 'N/A'
print(f'{ver}|{avail}|{gpu}')
" 2>/dev/null || echo "error|False|N/A"
        )

        local pt_ver pt_avail pt_gpu
        IFS='|' read -r pt_ver pt_avail pt_gpu <<< "$pt_result"

        if [ "$pt_avail" = "True" ]; then
            _diag_row "PyTorch"                   ok   "v${pt_ver} — GPU: ${pt_gpu}"
        elif [ "$pt_ver" = "error" ]; then
            _diag_row "PyTorch"                   fail "Import failed — reinstall base environment"
        else
            _diag_row "PyTorch"                   fail "v${pt_ver} — GPU not visible (check HSA vars)"
        fi
    else
        _diag_row "genai_env (inference venv)"    fail "Not found → Install Tools → Base Environment"
        _diag_row "PyTorch"                       info "Cannot check — genai_env missing"
    fi

    local kohya_venv="$HOME/kohya_env"
    if [ -d "$kohya_venv" ]; then
        _diag_row "kohya_env (training venv)"     ok   "$kohya_venv"
    else
        _diag_row "kohya_env (training venv)"     info "Not installed (kohya_ss is optional)"
    fi

    # ── User Settings ────────────────────────────────────────────────────────
    _diag_section "User Settings"

    local uenv="${USER_ENV:-$HOME/.config/rocm-wsl-ai/user.env}"
    if [ -f "$uenv" ]; then
        _diag_row "user.env"                      ok   "$uenv"
    else
        _diag_row "user.env"                      info "Not created — Settings → Edit Settings"
    fi

    local gpu_env="$HOME/.config/rocm-wsl-ai/gpu.env"
    if [ -f "$gpu_env" ]; then
        _diag_row "gpu.env (auto-detected)"       ok   "$gpu_env"
    else
        _diag_row "gpu.env (auto-detected)"       info "Not created (generated during install)"
    fi

    # ── Windows Host (WSL only) ──────────────────────────────────────────────
    if is_wsl; then
        _diag_section "Windows Host"

        local psh_cmd=""
        command -v powershell.exe >/dev/null 2>&1 && psh_cmd="powershell.exe"
        command -v pwsh.exe       >/dev/null 2>&1 && psh_cmd="pwsh.exe"

        if [ -n "$psh_cmd" ]; then
            local drv_info
            drv_info=$($psh_cmd -NoProfile -Command "
\$vc = Get-CimInstance Win32_VideoController |
      Where-Object { \$_.Name -like '*AMD*' -or \$_.Name -like '*Radeon*' } |
      Select-Object -First 1
if (\$vc) { Write-Output \"\$(\$vc.Name)|\$(\$vc.DriverVersion)\" }
" 2>/dev/null | tr -d '\r') || drv_info=""

            if [ -n "$drv_info" ]; then
                local drv_name drv_ver
                IFS='|' read -r drv_name drv_ver <<< "$drv_info"
                _diag_row "AMD Windows Driver"    ok   "${drv_name} — v${drv_ver}"
            else
                _diag_row "AMD Windows Driver"    warn "Could not query via PowerShell"
            fi
        else
            _diag_row "AMD Windows Driver"        info "PowerShell not accessible in WSL"
        fi
    fi

    # ── Summary ──────────────────────────────────────────────────────────────
    echo ""
    local core_ok=true
    command -v rocminfo >/dev/null 2>&1  || core_ok=false
    has_rocdxg                           || core_ok=false
    [ -f "$HOME/genai_env/bin/activate" ] || core_ok=false
    $gpu_found                           || core_ok=false   # GPU must actually be visible

    if $core_ok; then
        if command -v gum >/dev/null 2>&1; then
            gum style --foreground 46 --bold --margin "0 2" \
                "✅ Core stack looks healthy — ready for AI generation!"
        else
            echo "  [OK] Core stack looks healthy."
        fi
    else
        if ! $gpu_found && command -v rocminfo >/dev/null 2>&1; then
            # Special case: everything installed but GPU invisible — most actionable hint
            if command -v gum >/dev/null 2>&1; then
                gum style --foreground 196 --bold --margin "0 2" \
                    "✖  GPU not visible — run in Windows PowerShell:  wsl --shutdown"
            else
                echo "  [FAIL] GPU not visible. In Windows PowerShell: wsl --shutdown  then restart Ubuntu."
            fi
        else
            if command -v gum >/dev/null 2>&1; then
                gum style --foreground 214 --bold --margin "0 2" \
                    "⚠  Issues detected — check the FAIL/WARN items above."
            else
                echo "  [WARN] Issues detected — see FAIL/WARN items above."
            fi
        fi
    fi

    echo ""
    read -rp "  Press Enter to return..."
}

# ── Standalone entry point ────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_gpu_diag
fi
