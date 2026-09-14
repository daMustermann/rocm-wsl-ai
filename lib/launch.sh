#!/bin/bash
# ==============================================================================
# ROCm WSL AI Toolkit — Unified Launch Layer
# ==============================================================================
# Every tool start script sources this file. It owns:
#
#   1. The GPU environment. This is the single most important correctness fix in
#      the toolkit. HSA_ENABLE_DXG_DETECTION must be 1 *before the Python process
#      starts*, otherwise libhsa enumerates zero GPU agents and
#      torch.cuda.is_available() silently returns False. The old scripts relied
#      on the variable having been appended to the venv's `activate` script, so
#      anything that did not source `activate` (a fresh shell, an IDE, a cron
#      job, a userspace script) saw no GPU at all. Measured on gfx1100:
#      unset -> is_available() False; set -> True.
#
#   2. The tuned performance profile from perf_engine.py (MIOpen cache mode,
#      VRAM residency, precision), with the per-tool ComfyUI arguments.
#
#   3. Flag validation. ComfyUI's CLI grows over time; a flag this checkout does
#      not know would make it exit immediately. Flags are probed against the
#      installed --help output and dropped rather than passed blindly.
#
#   4. A lazy preflight. The old launcher ran a full `import torch` on every
#      single launch to check the GPU, costing seconds each time. Results are
#      now cached and only re-verified when the environment changes.
#
#   5. Idle hibernation that frees VRAM (formerly "Smart Sleep"), implemented
#      in-process instead of spawning two extra Python interpreters.
#
# Public entry point:  ai_launch
# ==============================================================================

# Guard against double-sourcing.
if [ -n "${_ROCM_AI_LAUNCH_LOADED:-}" ]; then
    return 0 2>/dev/null || true
fi
_ROCM_AI_LAUNCH_LOADED=1

TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROCM_AI_CONFIG_DIR="${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}"
ROCM_AI_USER_ENV="$ROCM_AI_CONFIG_DIR/user.env"
ROCM_AI_GPU_ENV="$ROCM_AI_CONFIG_DIR/gpu.env"
ROCM_AI_PERF_ENV="$ROCM_AI_CONFIG_DIR/perf.env"
ROCM_AI_PREFLIGHT_CACHE="$ROCM_AI_CONFIG_DIR/.preflight"
ROCM_AI_LOG_DIR="$ROCM_AI_CONFIG_DIR/logs"

# --- Colours (only when the terminal can show them) --------------------------
# Note this is not simply an isatty check: TERM=dumb is a tty but renders no
# escape sequences at all, which would leave prompts with no visible selection.
_rocm_ai_launch_colours_ok() {
    [ -n "${NO_COLOR:-}" ] && return 1
    case "${TERM:-dumb}" in ""|dumb|unknown) return 1 ;; esac
    if command -v tput >/dev/null 2>&1; then
        local n
        n="$(tput colors 2>/dev/null || echo "")"
        if [ -n "$n" ]; then
            [ "$n" -ge 8 ] 2>/dev/null && return 0 || return 1
        fi
    fi
    case "${TERM:-}" in *color*|*256*|xterm*|screen*|tmux*|rxvt*|linux|vt100|ansi|cygwin) return 0 ;; esac
    return 1
}

if [ -t 1 ] && _rocm_ai_launch_colours_ok; then
    _C_RESET=$'\033[0m'; _C_DIM=$'\033[2m'; _C_BOLD=$'\033[1m'
    _C_OK=$'\033[38;5;46m'; _C_WARN=$'\033[38;5;214m'; _C_ERR=$'\033[38;5;196m'
    _C_ACC=$'\033[38;5;212m'; _C_INFO=$'\033[38;5;117m'
else
    _C_RESET=""; _C_DIM=""; _C_BOLD=""; _C_OK=""; _C_WARN=""; _C_ERR=""; _C_ACC=""; _C_INFO=""
fi

ai_say()  { printf '%s\n' "$*"; }
ai_ok()   { printf '%s✔%s  %s\n' "$_C_OK" "$_C_RESET" "$*"; }
ai_warn() { printf '%s⚠%s  %s\n' "$_C_WARN" "$_C_RESET" "$*"; }
ai_err()  { printf '%s✖%s  %s\n' "$_C_ERR" "$_C_RESET" "$*" >&2; }
ai_info() { printf '%sℹ%s  %s\n' "$_C_INFO" "$_C_RESET" "$*"; }
ai_dim()  { printf '%s%s%s\n' "$_C_DIM" "$*" "$_C_RESET"; }

ai_banner() {
    printf '\n%s%s%s\n' "$_C_ACC" "$1" "$_C_RESET"
    printf '%s\n' "$(printf '─%.0s' $(seq 1 ${#1}))"
}

# ==============================================================================
# Environment
# ==============================================================================

# Is ROCDXG present? Its presence changes how HSA_OVERRIDE_GFX_VERSION behaves:
# with librocdxg, DXCore enumerates the GPU and an override makes
# topology_sysfs_get_node_props reject the device, hiding the GPU entirely.
ai_has_rocdxg() {
    [ -f /opt/rocm/lib/librocdxg.so ]
}

ai_is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

# Apply every environment layer in the correct order. Called by ai_launch before
# any Python process is spawned.
ai_load_env() {
    # 1. User settings (ports, manual GPU profile).
    if [ -f "$ROCM_AI_USER_ENV" ]; then
        set -a
        # shellcheck disable=SC1090
        . "$ROCM_AI_USER_ENV"
        set +a
    fi

    # 2. Auto-detected GPU environment.
    if [ -f "$ROCM_AI_GPU_ENV" ]; then
        # shellcheck disable=SC1090
        . "$ROCM_AI_GPU_ENV"
    fi

    # 3. Tuned performance profile (MIOpen mode, precision, ComfyUI args).
    if [ -f "$ROCM_AI_PERF_ENV" ]; then
        # shellcheck disable=SC1090
        . "$ROCM_AI_PERF_ENV"
    fi

    # 4. Non-negotiable requirements, applied last so nothing can undermine them.
    export HSA_ENABLE_DXG_DETECTION=1
    export PIP_USER=0

    if ai_has_rocdxg; then
        unset HSA_OVERRIDE_GFX_VERSION
    fi

    # 5. Make the MIOpen convolution tuning database persistent for ALL tools,
    #    not just the ones launched through the tuned profile. Without this every
    #    fresh process re-searches for the best convolution algorithm.
    export MIOPEN_USER_DB_PATH="${MIOPEN_USER_DB_PATH:-$ROCM_AI_CONFIG_DIR/miopen}"
    export MIOPEN_CUSTOM_CACHE_DIR="${MIOPEN_CUSTOM_CACHE_DIR:-$ROCM_AI_CONFIG_DIR/miopen}"
    mkdir -p "$MIOPEN_USER_DB_PATH" 2>/dev/null || true

    # 6. Strip the variable that segfaults torch 2.9.1+rocm7.2.3 on import.
    #    An older toolkit version appended this to the venv activate script, so
    #    it can still be lurking in a user's shell.
    if [ -n "${PYTORCH_HIP_ALLOC_CONF:-}" ]; then
        ai_warn "Ignoring PYTORCH_HIP_ALLOC_CONF — it crashes this PyTorch build."
        ai_dim  "        Remove it from ~/.bashrc or ~/.config/rocm-wsl-ai/user.env."
        unset PYTORCH_HIP_ALLOC_CONF
    fi
}

ai_require_venv() {
    local venv="$1"
    local activate="$HOME/$venv/bin/activate"
    if [ ! -f "$activate" ]; then
        ai_err "Python environment '$venv' not found at $HOME/$venv"
        ai_say "     Install it first:  ./menu.sh  ->  Install  ->  Base Environment"
        return 1
    fi
    # shellcheck disable=SC1090
    . "$activate"
    return 0
}

# ==============================================================================
# Preflight (cached)
# ==============================================================================
# The check itself is a few seconds of `import torch`, and computing the cache
# signature also costs about a second (it shells out to Python for the torch
# version). So the result is cached with a timestamp: inside PREFLIGHT_TTL the
# cache is trusted outright and a launch costs almost nothing, and beyond it the
# signature is recomputed to notice a driver or torch upgrade.

PREFLIGHT_TTL="${ROCM_AI_PREFLIGHT_TTL:-900}"

ai_preflight_signature() {
    local torch_ver driver sig
    torch_ver="$(python3 -c 'import torch;print(torch.__version__)' 2>/dev/null || echo none)"
    driver=""
    if command -v powershell.exe >/dev/null 2>&1; then
        driver="$(powershell.exe -NoProfile -Command \
            "(Get-CimInstance Win32_VideoController | Where-Object { \$_.Name -like '*AMD*' -or \$_.Name -like '*Radeon*' } | Select-Object -First 1).DriverVersion" \
            2>/dev/null | tr -d '\r\n')"
    fi
    sig="torch=${torch_ver};driver=${driver};rocdxg=$(ai_has_rocdxg && printf 'y' || printf 'n')"
    sig+=";dxg=${HSA_ENABLE_DXG_DETECTION:-0};gfx=${HSA_OVERRIDE_GFX_VERSION:-auto}"
    printf '%s' "$sig" | md5sum | cut -d' ' -f1
}

ai_preflight() {
    local force="${1:-}"

    # Fast path: a fresh, successful result is trusted without any subprocess.
    if [ "$force" != "force" ] && [ -f "$ROCM_AI_PREFLIGHT_CACHE" ]; then
        local stamp status age now
        stamp="$(sed -n '3p' "$ROCM_AI_PREFLIGHT_CACHE" 2>/dev/null)"
        status="$(sed -n '2p' "$ROCM_AI_PREFLIGHT_CACHE" 2>/dev/null)"
        if [ -n "$stamp" ]; then
            now="$(date +%s)"
            age=$(( now - stamp ))
            if [ "$status" = "ok" ] && [ "$age" -ge 0 ] && [ "$age" -lt "$PREFLIGHT_TTL" ]; then
                return 0
            fi
        fi
    fi

    local sig cached_sig cached_status sig_changed=1
    sig="$(ai_preflight_signature)"

    if [ "$force" != "force" ] && [ -f "$ROCM_AI_PREFLIGHT_CACHE" ]; then
        cached_sig="$(sed -n '1p' "$ROCM_AI_PREFLIGHT_CACHE" 2>/dev/null)"
        cached_status="$(sed -n '2p' "$ROCM_AI_PREFLIGHT_CACHE" 2>/dev/null)"
        if [ "$cached_sig" = "$sig" ] && [ "$cached_status" = "ok" ]; then
            # Environment unchanged and previously healthy: refresh the
            # timestamp and skip the expensive check.
            printf '%s\nok\n%s\n' "$sig" "$(date +%s)" > "$ROCM_AI_PREFLIGHT_CACHE"
            return 0
        fi
        [ "$cached_sig" = "$sig" ] && sig_changed=0
    fi

    local status="ok"

    if ai_is_wsl && ! ai_has_rocdxg; then
        ai_err "ROCDXG (librocdxg.so) is missing — ROCm cannot reach the GPU in WSL2."
        ai_say "     Fix:  ./menu.sh  ->  Install  ->  Repair / Upgrade ROCDXG"
        status="fail"
    fi

    local hip_out
    hip_out="$(python3 - <<'PY' 2>/dev/null
import torch
try:
    if torch.cuda.is_available():
        print("OK|%s|%s" % (torch.cuda.get_device_name(0), torch.__version__))
    else:
        print("NOGPU|")
except Exception as exc:
    print("ERR|%s" % str(exc)[:80])
PY
)" || hip_out="ERR|python failed"

    case "${hip_out%%|*}" in
        OK)
            ai_ok "GPU ready: $(printf '%s' "$hip_out" | cut -d'|' -f2)  (torch $(printf '%s' "$hip_out" | cut -d'|' -f3))"
            ;;
        NOGPU)
            ai_err "PyTorch cannot see any HIP/ROCm GPU."
            ai_say ""
            ai_say "  ${_C_BOLD}Most likely fixes, in order:${_C_RESET}"
            ai_say "   1. In Windows PowerShell:  wsl --shutdown     then reopen Ubuntu"
            ai_say "      (group membership and the DXCore bridge need a restart)"
            ai_say "   2. AMD Adrenalin 26.2.2 or newer on Windows"
            ai_say "   3. Full diagnosis:  ./menu.sh  ->  Settings  ->  GPU Diagnostics"
            ai_say ""
            status="fail"
            ;;
        *)
            ai_err "PyTorch import failed: $(printf '%s' "$hip_out" | cut -d'|' -f2)"
            status="fail"
            ;;
    esac

    mkdir -p "$ROCM_AI_CONFIG_DIR" 2>/dev/null || true
    printf '%s\n%s\n%s\n' "$sig" "$status" "$(date +%s)" > "$ROCM_AI_PREFLIGHT_CACHE" 2>/dev/null || true

    [ "$status" = "ok" ]
}

# ==============================================================================
# Flag validation
# ==============================================================================

# Keep only the flags the installed ComfyUI actually accepts. A stale or
# unknown flag makes ComfyUI exit before it ever loads a model, which is a
# confusing failure; dropping it degrades gracefully instead.
ai_filter_comfyui_args() {
    local help_text="$1"; shift
    local -a kept=()
    local flag
    for flag in "$@"; do
        if printf '%s' "$help_text" | grep -q -- "$flag"; then
            kept+=("$flag")
        else
            ai_warn "Dropping unsupported ComfyUI flag for this version: $flag"
        fi
    done
    printf '%s\n' "${kept[@]:-}"
}

ai_comfyui_help() {
    local dir="$1"
    ( cd "$dir" 2>/dev/null && python3 main.py --help 2>/dev/null ) || true
}

# ==============================================================================
# Idle hibernation ("Smart Sleep")
# ==============================================================================
# Runs the server in the background and watches its output. After
# SMART_SLEEP_TIMEOUT seconds with no new output the server is asked to stop,
# which releases the whole VRAM allocation back to Windows. A tiny HTTP server
# then answers on the same port so that refreshig the browser page restarts the
# real server — the user experience is "the page reloads and it comes back".

ai_sleep_timeout() {
    printf '%s' "${SMART_SLEEP_TIMEOUT:-1800}"
}

ai_run_with_hibernation() {
    local port="$1"; shift
    local timeout; timeout="$(ai_sleep_timeout)"

    if [ "${SMART_SLEEP_DISABLE:-0}" = "1" ]; then
        "$@"
        return $?
    fi

    local timeout_label
    if [ "$timeout" -ge 60 ] 2>/dev/null; then
        timeout_label="$((timeout / 60)) min"
    else
        timeout_label="${timeout}s"
    fi

    ai_dim "  Idle hibernation: ${timeout_label} (frees VRAM; the browser page wakes it)"

    # One log file per session; its mtime is the activity signal.
    local log
    log="$(mktemp -t rocm-ai-run.XXXXXX)"

    while true; do
        : > "$log"

        # Run the server with its stdout/stderr piped through tee, so that:
        #   * the user sees live output,
        #   * activity can be observed via the log's mtime,
        #   * the server inherits our terminal stdin and stays in our process
        #     group, so Ctrl+C reaches it the same way it always did.
        "$@" > >(tee "$log") 2>&1 &
        local pid=$!

        # Forward a Ctrl+C to the server while we are waiting, then stop waiting.
        local interrupted=0
        trap 'interrupted=1' INT

        local last_activity now elapsed
        last_activity="$(date +%s)"

        while kill -0 "$pid" 2>/dev/null; do
            sleep 5
            # Force the redirect to flush into the log promptly.
            if [ -f "$log" ]; then
                local mtime
                mtime="$(stat -c %Y "$log" 2>/dev/null || echo "$last_activity")"
                if [ "$mtime" -gt "$last_activity" ] 2>/dev/null; then
                    last_activity="$mtime"
                fi
            fi

            if [ "$interrupted" = "1" ]; then
                kill -INT "$pid" 2>/dev/null || true
                break
            fi

            now="$(date +%s)"
            elapsed=$(( now - last_activity ))
            if [ "$elapsed" -ge "$timeout" ]; then
                ai_say ""
                ai_warn "Idle for ${timeout_label} — stopping the server to free VRAM."
                kill -INT "$pid" 2>/dev/null || true
                local waited=0
                while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 20 ]; do
                    sleep 0.5
                    waited=$((waited + 1))
                done
                if kill -0 "$pid" 2>/dev/null; then
                    ai_warn "Server did not stop cleanly — forcing it."
                    kill -9 "$pid" 2>/dev/null || true
                fi
                wait "$pid" 2>/dev/null || true
                trap - INT

                # Serve the wake page until somebody visits it.
                ai_dim "  Sleeping. Open http://localhost:${port} to wake it back up."
                python3 "$TOOLKIT_ROOT/scripts/utils/wake_server.py" "$port"

                # Loop round and restart the real server.
                continue 2
            fi
        done

        trap - INT
        wait "$pid" 2>/dev/null
        local code=$?
        rm -f "$log"
        return "$code"
    done
}

# ==============================================================================
# Public entry point
# ==============================================================================

# ai_launch --name "ComfyUI" --dir ~/ComfyUI --command "python main.py" \
#           --port 8188 --health / --venv genai_env [--args "--listen 0.0.0.0"] \
#           [--allow-extra-args] [--preflight-force]
ai_launch() {
    local name="" dir="" command="" port="" health="/" venv="" tool_key=""
    local allow_extra_args=0 preflight_force=0 no_hibernate=0
    local -a extra_args=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --name)             name="$2"; shift 2 ;;
            --dir)              dir="$2"; shift 2 ;;
            --command)          command="$2"; shift 2 ;;
            --port)             port="$2"; shift 2 ;;
            --health)           health="$2"; shift 2 ;;
            --venv)             venv="$2"; shift 2 ;;
            --tool-key)         tool_key="$2"; shift 2 ;;
            --allow-extra-args) allow_extra_args=1; shift ;;
            --preflight-force)  preflight_force=1; shift ;;
            --no-hibernate)     no_hibernate=1; shift ;;
            --)                 shift; extra_args=("$@"); break ;;
            *)                  shift ;;
        esac
    done

    ai_banner "Starting $name"

    ai_load_env

    # --- Environment report ---------------------------------------------------
    if [ -n "$port" ]; then
        ai_info "URL   : http://localhost:$port"
    fi
    if [ -n "$ROCM_AI_PERF_PROFILE" ]; then
        ai_info "Tuning: profile '$ROCM_AI_PERF_PROFILE'"
    else
        ai_dim  "Tuning: not tuned yet (menu -> Performance -> Auto-Tune for speed)"
    fi

    # --- Validate the tool is installed --------------------------------------
    if [ -n "$dir" ] && [ ! -d "$dir" ]; then
        ai_err "$name is not installed (missing $dir)"
        ai_say "     Install it:  ./menu.sh  ->  Install  ->  $name"
        return 1
    fi

    # --- Activate the Python environment -------------------------------------
    if [ -n "$venv" ]; then
        ai_require_venv "$venv" || return 1
    fi

    # --- GPU preflight --------------------------------------------------------
    if [ "$preflight_force" = "1" ]; then
        ai_preflight force || return 1
    else
        ai_preflight || return 1
    fi

    # --- Assemble the command -------------------------------------------------
    local full_command="$command"

    # ComfyUI-specific: append the tuned profile's arguments, validated against
    # this checkout's actual --help output.
    if [ "$tool_key" = "comfyui" ] && [ -n "$dir" ]; then
        local -a profile_args=()
        if [ -n "${ROCM_AI_COMFYUI_ARGS:-}" ]; then
            # shellcheck disable=SC2206
            profile_args=($ROCM_AI_COMFYUI_ARGS)
        fi
        if [ "${#profile_args[@]}" -gt 0 ]; then
            local help_text
            help_text="$(ai_comfyui_help "$dir")"
            if [ -n "$help_text" ]; then
                local accepted
                accepted="$(ai_filter_comfyui_args "$help_text" "${profile_args[@]}")"
                local -a validated=()
                while IFS= read -r line; do
                    [ -n "$line" ] && validated+=("$line")
                done <<< "$accepted"
                if [ "${#validated[@]}" -gt 0 ]; then
                    full_command="$full_command ${validated[*]}"
                    ai_ok "Applied tuned flags: ${validated[*]}"
                fi
            else
                full_command="$full_command ${profile_args[*]}"
                ai_dim "  (could not read ComfyUI --help; passing tuned flags unverified)"
            fi
        fi
    fi

    # --- Extra arguments ------------------------------------------------------
    if [ "${#extra_args[@]}" -gt 0 ]; then
        if [ "$allow_extra_args" = "1" ] || [ "$#" -eq 0 ]; then
            full_command="$full_command ${extra_args[*]}"
        fi
    fi

    # --- Serve ----------------------------------------------------------------
    local -a serve
    serve=(bash -c "cd $(printf '%q' "$dir") && exec $full_command")

    printf '\n%s%s%s\n' "$_C_BOLD" "  $ $full_command" "$_C_RESET"
    printf '%s\n\n' "$(printf '─%.0s' $(seq 1 60))"

    mkdir -p "$ROCM_AI_LOG_DIR" 2>/dev/null || true

    # Notify Windows users that the page is up — WSL cannot open their browser,
    # so print the address prominently instead (the desktop shortcut already
    # does the opening on the Windows side).
    if [ -n "$port" ]; then
        printf '  %sOpen in your Windows browser:%s  %shttp://localhost:%s%s\n\n' \
            "$_C_ACC" "$_C_RESET" "$_C_BOLD" "$port" "$_C_RESET"
    fi

    local exit_code=0
    if [ "$no_hibernate" = "1" ] || [ -z "$port" ]; then
        "${serve[@]}"
        exit_code=$?
    else
        ai_run_with_hibernation "$port" "${serve[@]}"
        exit_code=$?
    fi

    printf '\n'
    if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 130 ]; then
        ai_ok "$name stopped. VRAM released."
    else
        ai_err "$name exited with code $exit_code."
        ai_say "     Common causes:"
        ai_say "       - Port ${port:-?} already in use:  ./menu.sh -> Tools -> Stop all AI servers"
        ai_say "       - Missing Python dependency: reinstall the tool from the menu"
        ai_say "       - Full diagnosis:                ./menu.sh -> Settings -> GPU Diagnostics"
    fi
    return "$exit_code"
}

# ------------------------------------------------------------------------------
# Is a given port currently served, and by what? Used by the status dashboard.
# ------------------------------------------------------------------------------
ai_port_pid() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltnp 2>/dev/null | awk -v p=":$port" '$4 ~ p {print}' \
            | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2
    elif command -v lsof >/dev/null 2>&1; then
        lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -1
    fi
}

ai_port_busy() {
    [ -n "$(ai_port_pid "$1")" ]
}