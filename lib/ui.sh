#!/bin/bash
# ==============================================================================
# ROCm WSL AI Toolkit — UI / state presentation layer
# ==============================================================================
# Everything that turns machine state into something a human reads. Kept out of
# menu.sh so that it can be tested without a terminal and reused by other
# front-ends.
#
# Depends on: lib/common.sh, lib/launch.sh, lib/tools.sh
# ==============================================================================

if [ -n "${_ROCM_AI_UI_LOADED:-}" ]; then
    return 0 2>/dev/null || true
fi
_ROCM_AI_UI_LOADED=1

# lib/launch.sh defines these only when stdout is a terminal, so anything reading
# them unconditionally breaks as soon as output is redirected or piped. Fall back
# to empty strings rather than relying on the caller's terminal.
: "${_C_RESET:=}"
: "${_C_BOLD:=}"
: "${_C_DIM:=}"
: "${_C_OK:=}"
: "${_C_WARN:=}"
: "${_C_ERR:=}"
: "${_C_ACC:=}"
: "${_C_INFO:=}"

# This library presents state that other libraries produce. Sourcing it alone
# yields a pile of "command not found" errors the moment anything is rendered,
# which reads like a broken install rather than a missing dependency. Say so
# plainly instead, and tell the reader what to do about it.
if ! declare -f rocm_ai_all_tool_keys >/dev/null 2>&1 \
   || ! declare -f _rocm_ai_have_gum >/dev/null 2>&1; then
    printf '%s\n' \
        "lib/ui.sh: dependencies not loaded." \
        "           Source lib/common.sh, lib/launch.sh and lib/tools.sh first:" \
        "" \
        "             . lib/common.sh" \
        "             . lib/launch.sh" \
        "             . lib/tools.sh" \
        "             . lib/ui.sh" >&2
    return 1 2>/dev/null || exit 1
fi

# Paths this library reads that are normally defined by lib/launch.sh.
: "${ROCM_AI_PERF_ENV:=${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}/perf.env}"

# --- Python interpreter for the active environment ----------------------------
rocm_ai_venv_python() {
    if [ -x "$HOME/genai_env/bin/python3" ]; then
        printf '%s' "$HOME/genai_env/bin/python3"
    else
        printf '%s' "python3"
    fi
}

# --- GPU description ----------------------------------------------------------
# Cached: rocminfo takes a second or two and the home screen redraws often.
GPU_SUMMARY_TTL="${ROCM_AI_GPU_SUMMARY_TTL:-600}"

gpu_summary() {
    local cache="$ROCM_AI_CONFIG_DIR/.gpu_summary"

    if [ -f "$cache" ]; then
        local age now
        now="$(date +%s)"
        age=$(( now - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
        if [ "$age" -ge 0 ] && [ "$age" -lt "$GPU_SUMMARY_TTL" ]; then
            cat "$cache"
            return 0
        fi
    fi

    local summary="" rocm_out name vram
    if command -v rocminfo >/dev/null 2>&1; then
        rocm_out="$(HSA_ENABLE_DXG_DETECTION=1 timeout 30 rocminfo 2>/dev/null || true)"
        name="$(printf '%s' "$rocm_out" | grep -E 'Marketing Name:' \
            | grep -iE 'radeon|amd' | head -1 | sed 's/.*Marketing Name: *//' | xargs)"
        vram="$(printf '%s' "$rocm_out" \
            | awk '/Marketing Name:.*(Radeon|AMD)/{f=1} f&&/Pool 1/{p=1} p&&/Size:/{print $2; exit}' \
            | cut -d'(' -f1)"
        if [ -n "$name" ]; then
            if [[ "$vram" =~ ^[0-9]+$ ]] && [ "$vram" -gt 0 ]; then
                summary="$name · $((vram / 1024 / 1024)) GB"
            else
                summary="$name"
            fi
        fi
    fi

    if [ -z "$summary" ]; then
        if ai_has_rocdxg; then
            summary="no AMD GPU found by rocminfo"
        else
            summary="ROCm not installed yet"
        fi
    fi

    # Create the directory first: on a fresh install nothing has made it yet, and
    # redirecting into a missing directory prints a shell error for every caller.
    mkdir -p "$ROCM_AI_CONFIG_DIR" 2>/dev/null || true
    printf '%s' "$summary" > "$cache" 2>/dev/null || true
    printf '%s' "$summary"
}

# --- Engine description -------------------------------------------------------
# `import torch` costs well over a second, so this is cached too.
ENGINE_SUMMARY_TTL="${ROCM_AI_ENGINE_SUMMARY_TTL:-300}"

engine_summary() {
    if [ ! -f "$HOME/genai_env/bin/activate" ]; then
        printf 'not installed yet'
        return 0
    fi

    local cache="$ROCM_AI_CONFIG_DIR/.engine_summary"
    if [ -f "$cache" ]; then
        local age now
        now="$(date +%s)"
        age=$(( now - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
        if [ "$age" -ge 0 ] && [ "$age" -lt "$ENGINE_SUMMARY_TTL" ]; then
            cat "$cache"
            return 0
        fi
    fi

    local summary
    summary="$(HSA_ENABLE_DXG_DETECTION=1 "$(rocm_ai_venv_python)" -c '
import torch
try:
    print(torch.__version__, "· GPU ready" if torch.cuda.is_available() else "· GPU NOT visible")
except Exception:
    print("status unknown")
' 2>/dev/null || printf 'status unknown')"
    [ -z "$summary" ] && summary="status unknown"

    mkdir -p "$ROCM_AI_CONFIG_DIR" 2>/dev/null || true
    printf '%s' "$summary" > "$cache" 2>/dev/null || true
    printf '%s' "$summary"
}

# --- Tuning profile ----------------------------------------------------------
perf_profile_label() {
    if [ -f "$ROCM_AI_PERF_ENV" ]; then
        local p
        p="$(sed -n 's/^export ROCM_AI_PERF_PROFILE="\(.*\)"/\1/p' "$ROCM_AI_PERF_ENV" | head -1)"
        [ -n "$p" ] && { printf '%s' "$p"; return 0; }
    fi
    printf 'not tuned'
}

# --- Tools ------------------------------------------------------------------
installed_tool_count() {
    local n=0 key
    for key in $(rocm_ai_all_tool_keys); do
        rocm_ai_tool_installed "$key" && n=$((n + 1))
    done
    printf '%s' "$n"
}

# Is this tool currently serving on its port?
tool_running() {
    local key="$1" port
    port="$(rocm_ai_tool_effective_port "$key")"
    [ "$port" = "-" ] && return 1
    ai_port_busy "$port"
}

# A compact aligned list of installed tools and whether they are up.
tool_status_lines() {
    local any=0 key name state port
    for key in $(rocm_ai_all_tool_keys); do
        rocm_ai_tool_installed "$key" || continue
        any=1
        name="$(rocm_ai_tool_name "$key")"
        port="$(rocm_ai_tool_effective_port "$key")"
        if tool_running "$key"; then
            state="${_C_OK}running${_C_RESET}"
        else
            state="${_C_DIM}stopped${_C_RESET}"
        fi
        printf '     %-24s %b' "$name" "$state"
        if [ "$port" != "-" ]; then
            printf '  %bhttp://localhost:%s%b' "$_C_DIM" "$port" "$_C_RESET"
        fi
        printf '\n'
    done
    [ "$any" = "0" ] && printf '     %bNo tools installed yet.%b\n' "$_C_DIM" "$_C_RESET"
    return 0
}

# Recommended next action, derived from actual state. This is what makes the
# home screen useful rather than a wall of options.
recommended_next_step() {
    if [ ! -f "$HOME/genai_env/bin/activate" ]; then
        printf 'Install the base environment — choose "Quick start" below'
        return 0
    fi
    if ! ai_has_rocdxg 2>/dev/null; then
        printf 'Repair the ROCDXG GPU bridge — Install -> Upgrade / repair'
        return 0
    fi

    # An available upgrade outranks tuning: the new stack changes the
    # measurements, so tuning first would be wasted work.
    if declare -f upgrade_available >/dev/null 2>&1 && upgrade_available; then
        printf 'A newer ROCm is available — Updates -> Upgrade everything automatically'
        return 0
    fi

    if [ "$(installed_tool_count)" = "0" ]; then
        printf 'Install an AI tool — choose "Quick start" below'
        return 0
    fi
    if [ "$(perf_profile_label)" = "not tuned" ]; then
        printf 'Run the GPU tuner — Performance -> Auto-tune for this GPU'
        return 0
    fi
    local key port
    for key in $(rocm_ai_all_tool_keys); do
        if rocm_ai_tool_installed "$key" && tool_running "$key"; then
            port="$(rocm_ai_tool_effective_port "$key")"
            printf '%s is running — open http://localhost:%s' "$(rocm_ai_tool_name "$key")" "$port"
            return 0
        fi
    done
    printf 'Launch a tool — Launch -> pick one'
}

# Is a newer ROCm release published for this Ubuntu version than is installed?
# Cached through lib/version.sh, so this is cheap after the first call.
upgrade_available() {
    declare -f va_latest_rocm >/dev/null 2>&1 || return 1
    local now new codename
    now="$(va_rocm_installed 2>/dev/null || true)"
    [ -n "$now" ] || return 1
    codename="$(va_ubuntu_codename)"
    new="$(va_latest_rocm "$codename" 2>/dev/null || true)"
    [ -n "$new" ] || return 1
    va_lt "$now" "$new"
}

# ------------------------------------------------------------------------------
# Home screen
# ------------------------------------------------------------------------------
render_home() {
    clear
    local installed
    installed="$(installed_tool_count)"

    printf '\n'
    if _rocm_ai_have_gum; then
        gum style --border double --margin "0 2" --padding "0 2" --border-foreground 212 \
            --align center \
            "$(gum style --bold --foreground 212 "ROCm WSL2 AI Toolkit  v${ROCM_AI_VERSION}")" \
            "$(gum style --foreground 240 "high-performance AMD AI on Windows, without the setup pain")"
    else
        printf '%b============================================================%b\n' "$MAGENTA" "$NC"
        printf '   ROCm WSL2 AI Toolkit  v%s\n' "$ROCM_AI_VERSION"
        printf '%b============================================================%b\n' "$MAGENTA" "$NC"
    fi
    printf '\n'

    printf '   %bGPU%b        %s\n' "$BOLD" "$NC" "$(gpu_summary)"
    printf '   %bEngine%b     %b%s%b\n' "$BOLD" "$NC" "$_C_DIM" "$(engine_summary)" "$_C_RESET"
    printf '   %bTuning%b     %s\n' "$BOLD" "$NC" "$(perf_profile_label)"
    printf '   %bTools%b      %s installed\n' "$BOLD" "$NC" "$installed"
    printf '\n'

    if [ "$installed" != "0" ]; then
        printf '   %bInstalled tools%b\n' "$BOLD" "$NC"
        tool_status_lines
        printf '\n'
    fi

    printf '   %bNext step%b  %b%s%b\n' "$BOLD" "$NC" "$_C_ACC" "$(recommended_next_step)" "$_C_RESET"
    printf '\n'
}
