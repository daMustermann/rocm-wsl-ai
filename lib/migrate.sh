#!/bin/bash
# ==============================================================================
# ROCm WSL AI Toolkit — Configuration migration
# ==============================================================================
# Upgrading the toolkit is only half an upgrade. A machine that has been running
# version 3.x carries configuration that is not merely stale but actively
# harmful, and leaving it in place would quietly undo the fixes in 4.x. The most
# serious example: older versions appended PYTORCH_HIP_ALLOC_CONF to the
# virtualenv's activate script, and that variable segfaults PyTorch
# 2.9.1+rocm7.2.3 on import.
#
# Every migration step is:
#   * idempotent      — running it twice changes nothing
#   * non-destructive — the affected file is backed up before editing
#   * reported        — the user is told exactly what changed and why
#   * reversible      — each change prints how to undo it
#
# Nothing here touches models, custom nodes, extensions or datasets.
# ==============================================================================

if [ -n "${_ROCM_AI_MIGRATE_LOADED:-}" ]; then
    return 0 2>/dev/null || true
fi
_ROCM_AI_MIGRATE_LOADED=1

# Bookkeeping: what was changed, for the closing summary.
MIGRATION_ACTIONS=()

_mig_action() { MIGRATION_ACTIONS+=("$1"); }
_mig_note()   { printf '     %s\n' "$*"; }

# Back up a file once per run, preserving its mode.
_mig_backup() {
    local file="$1"
    [ -f "$file" ] || return 0
    local backup="${file}.pre-4.1.$(date +%Y%m%d%H%M%S)"
    cp -p "$file" "$backup" 2>/dev/null && printf '%s' "$backup"
}

# ------------------------------------------------------------------------------
# 1. PYTORCH_HIP_ALLOC_CONF — the segfault trap
# ------------------------------------------------------------------------------
# Older versions wrote this into the venv activate script and, in some revisions,
# into shell rc files. On torch 2.9.1+rocm7.2.3 it causes an immediate SIGSEGV
# during `import torch`, which surfaces to users as "PyTorch is broken".
rocm_ai_migrate_pytorch_alloc_conf() {
    local fixed=0

    local -a targets=(
        "$HOME/genai_env/bin/activate"
        "$HOME/kohya_env/bin/activate"
        "$HOME/.bashrc"
        "$HOME/.profile"
        "$HOME/.bash_profile"
        "${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}/user.env"
    )

    local file
    for file in "${targets[@]}"; do
        [ -f "$file" ] || continue
        grep -qE '^[[:space:]]*(export[[:space:]]+)?PYTORCH_HIP_ALLOC_CONF=' "$file" 2>/dev/null || continue

        local backup
        backup="$(_mig_backup "$file")"
        # Comment out rather than delete, so the change is visible and reversible.
        sed -i -E 's|^([[:space:]]*(export[[:space:]]+)?)PYTORCH_HIP_ALLOC_CONF=.*|# [4.1 migration] removed: this variable segfaults PyTorch 2.9.1+rocm7.2.3\n# \1PYTORCH_HIP_ALLOC_CONF disabled|' "$file"
        _mig_note "Removed PYTORCH_HIP_ALLOC_CONF from ${file/#$HOME/\~}"
        [ -n "$backup" ] && _mig_note "  backup: ${backup/#$HOME/\~}"
        fixed=$((fixed + 1))
    done

    if [ "$fixed" -gt 0 ]; then
        _mig_action "Disabled PYTORCH_HIP_ALLOC_CONF in $fixed file(s) — it crashes PyTorch on import"
    fi
    # Also clear it for the current session so nothing downstream inherits it.
    unset PYTORCH_HIP_ALLOC_CONF
    return 0
}

# ------------------------------------------------------------------------------
# 2. Obsolete tuning profile
# ------------------------------------------------------------------------------
# 3.x wrote ~/.genai_opt_profile containing MIGRAPHX_MLIR_USE_SPECIFIC_OPS and
# PYTORCH_ALLOC_CONF settings, sourced by every launcher. Those variables do not
# influence PyTorch's HIP backend, so the file had no effect beyond confusing
# anyone who read it. It is now superseded by perf.env.
rocm_ai_migrate_old_tuning_profile() {
    local old="$HOME/.genai_opt_profile"
    [ -f "$old" ] || return 0

    local backup
    backup="$(_mig_backup "$old")"
    mv "$old" "${old}.obsolete-3.x" 2>/dev/null || return 0

    _mig_note "Retired ~/.genai_opt_profile (settings it contained had no effect)"
    [ -n "$backup" ] && _mig_note "  kept as: ${backup/#$HOME/\~}"
    _mig_note "  replaced by: ~/.config/rocm-wsl-ai/perf.env"

    # Warn if the user has not tuned the new engine yet.
    if [ ! -f "${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}/perf.env" ]; then
        _mig_note "  run Performance -> Auto-tune once to generate a measured profile"
    fi

    _mig_action "Retired the obsolete ~/.genai_opt_profile (its variables did not affect PyTorch)"
    return 0
}

# ------------------------------------------------------------------------------
# 3. Legacy GPU environment
# ------------------------------------------------------------------------------
# gpu.env was produced by the old auto-detection, which could bake in a
# HSA_OVERRIDE_GFX_VERSION. With ROCDXG that override hides the GPU from PyTorch
# entirely, so a stale gpu.env is a landmine: it is sourced on every launch.
rocm_ai_migrate_gpu_env() {
    local gpu_env="${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}/gpu.env"
    [ -f "$gpu_env" ] || { rm -f "$gpu_env.pre-4.1."* 2>/dev/null; return 0; }

    local removed_override=0
    if grep -qE '^[[:space:]]*export[[:space:]]+HSA_OVERRIDE_GFX_VERSION=' "$gpu_env" 2>/dev/null; then
        local backup
        backup="$(_mig_backup "$gpu_env")"
        sed -i -E 's|^([[:space:]]*export[[:space:]]+)HSA_OVERRIDE_GFX_VERSION=.*|# [4.1 migration] removed: hides the GPU when ROCDXG is installed|' "$gpu_env"
        removed_override=1
        _mig_note "Removed HSA_OVERRIDE_GFX_VERSION from gpu.env (it hides the GPU under ROCDXG)"
        [ -n "$backup" ] && _mig_note "  backup: ${backup/#$HOME/\~}"
    fi

    if [ "$removed_override" = "1" ]; then
        _mig_action "Cleaned a stale HSA_OVERRIDE_GFX_VERSION out of gpu.env"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# 4. Stale caches written by 3.x
# ------------------------------------------------------------------------------
# The preflight cache key format changed, and the GPU/engine summary caches hold
# results produced with the old (wrong) configuration. Clearing them costs one
# slow launch and prevents 4.x reporting stale hardware state.
rocm_ai_migrate_caches() {
    local dir="${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}"
    local removed=0 f
    for f in .preflight .gpu_summary .engine_summary gpu.env.tmp perf.env.tmp perf_profile.json.tmp; do
        if [ -e "$dir/$f" ]; then
            rm -f "$dir/$f" && removed=$((removed + 1))
        fi
    done
    if [ "$removed" -gt 0 ]; then
        _mig_note "Cleared $removed stale cache file(s) so 4.x re-detects fresh"
        _mig_action "Cleared $removed stale cache file(s) from the old version"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# 5. Settings file: add anything 4.x expects but 3.x never created
# ------------------------------------------------------------------------------
rocm_ai_migrate_user_env() {
    local user_env="${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}/user.env"
    [ -f "$user_env" ] || return 0

    local added=0

    # 4.x adds a Text Generation WebUI port and a hibernation setting.
    if ! grep -q 'TEXTGEN_PORT' "$user_env" 2>/dev/null; then
        printf '\nexport TEXTGEN_PORT=""    # default 5000\n' >> "$user_env"
        added=$((added + 1))
    fi
    if ! grep -qE 'SMART_SLEEP_(TIMEOUT|DISABLE)' "$user_env" 2>/dev/null; then
        printf '# Idle time before a tool is stopped and its VRAM released (0 = never).\nexport SMART_SLEEP_TIMEOUT=1800\n' >> "$user_env"
        added=$((added + 1))
    fi
    # The old, misleading comment block.
    if grep -q 'HSA_OVERRIDE_GFX_VERSION removed: breaks ROCDXG' "$user_env" 2>/dev/null; then
        sed -i 's|^# HSA_OVERRIDE_GFX_VERSION removed: breaks ROCDXG DXCore detection$|# HSA_OVERRIDE_GFX_VERSION: leave unset. With ROCDXG, an override hides your GPU.|' "$user_env"
    fi

    if [ "$added" -gt 0 ]; then
        _mig_note "Added $added new setting(s) to user.env"
        _mig_action "Updated user.env with settings introduced in 4.x"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# 6. Tool shortcuts written by the buggy generator
# ------------------------------------------------------------------------------
# Before 3.3.0, create_shortcut.sh emitted `wsl.exe %s ~ -e bash -ic ...`, which
# produces a window that closes instantly. Those .bat files litter the user's
# Windows desktop and look like the toolkit is broken.
rocm_ai_migrate_shortcuts() {
    ai_is_wsl 2>/dev/null || return 0
    command -v cmd.exe >/dev/null 2>&1 || return 0

    local win_profile desktop
    win_profile="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r\n')"
    [ -n "$win_profile" ] || return 0
    desktop="$(wslpath "$win_profile/Desktop" 2>/dev/null)"
    [ -d "$desktop" ] || return 0

    local found=0 bat
    for bat in "$desktop"/*.bat; do
        [ -f "$bat" ] || continue
        if grep -q -- '-e bash -ic' "$bat" 2>/dev/null; then
            mv "$bat" "${bat}.broken-backup" 2>/dev/null && found=$((found + 1))
        fi
    done

    if [ "$found" -gt 0 ]; then
        _mig_note "Disabled $found broken desktop shortcut(s) from an older version"
        _mig_note "  they were renamed to *.bat.broken-backup"
        _mig_note "  recreate working ones from: Desktop shortcut"
        _mig_action "Disabled $found broken desktop shortcut(s) that closed instantly"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# 7. Deprecated requirement pins
# ------------------------------------------------------------------------------
# Detect the CUDA-torch contamination that the old updater could cause by passing
# a requirements.txt straight to pip.
rocm_ai_migrate_check_torch_integrity() {
    local py="$HOME/genai_env/bin/python3"
    [ -x "$py" ] || return 0

    local hip
    hip="$("$py" -c 'import torch; print(torch.version.hip or "")' 2>/dev/null)"
    if [ -z "$hip" ]; then
        if "$py" -c 'import torch' 2>/dev/null; then
            _mig_note "PyTorch is installed but has no HIP support (a CUDA build?)"
            _mig_note "  the base environment will be rebuilt during this upgrade"
            _mig_action "Detected a non-ROCm PyTorch build — rebuilding the environment"
        fi
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Orchestrator
# ------------------------------------------------------------------------------
rocm_ai_migrate_config() {
    MIGRATION_ACTIONS=()

    printf '\n'
    log "Checking your existing configuration for settings that 4.x changed..."
    printf '\n'

    rocm_ai_migrate_pytorch_alloc_conf
    rocm_ai_migrate_old_tuning_profile
    rocm_ai_migrate_gpu_env
    rocm_ai_migrate_caches
    rocm_ai_migrate_user_env
    rocm_ai_migrate_shortcuts
    rocm_ai_migrate_check_torch_integrity

    printf '\n'
    if [ "${#MIGRATION_ACTIONS[@]}" -eq 0 ]; then
        success "Configuration already up to date — nothing needed changing."
    else
        success "Configuration migrated (${#MIGRATION_ACTIONS[@]} change(s)):"
        local a
        for a in "${MIGRATION_ACTIONS[@]}"; do
            printf '       • %s\n' "$a"
        done
    fi
    printf '\n'
    return 0
}

# Are there any pending migration actions? Used to decide whether to offer the
# migration step at all.
rocm_ai_migration_needed() {
    local user_env="${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}/user.env"
    local gpu_env="${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}/gpu.env"

    [ -f "$HOME/.genai_opt_profile" ] && return 0

    local f
    for f in "$HOME/genai_env/bin/activate" "$HOME/kohya_env/bin/activate" \
             "$HOME/.bashrc" "$HOME/.profile" "$user_env"; do
        [ -f "$f" ] && grep -qE '^[[:space:]]*(export[[:space:]]+)?PYTORCH_HIP_ALLOC_CONF=' "$f" 2>/dev/null && return 0
    done

    [ -f "$gpu_env" ] && grep -qE '^[[:space:]]*export[[:space:]]+HSA_OVERRIDE_GFX_VERSION=' "$gpu_env" 2>/dev/null && return 0

    return 1
}
