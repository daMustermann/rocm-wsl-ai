#!/bin/bash
# ==============================================================================
# Thin installer wrappers
# ==============================================================================
# lib/tools.sh owns tool installation. These wrappers exist so that the historical
# entry points keep working:
#
#   scripts/install/comfyui.sh
#   scripts/install/sdnext.sh
#   scripts/install/kohya_ss.sh
#
# They used to contain their own divergent copies of the install logic, which is
# how the toolkit ended up with install-time and update-time behaviour that
# disagreed with each other. There is now exactly one implementation.
#
# Sourced by those wrappers; not meant to be executed directly.
# ==============================================================================

if [ -n "${_ROCM_AI_SHIM_LOADED:-}" ]; then
    return 0 2>/dev/null || true
fi
_ROCM_AI_SHIM_LOADED=1

# rocm_ai_shim_bootstrap <script-dir>  — load the libraries a wrapper needs.
rocm_ai_shim_bootstrap() {
    local script_dir="$1"
    local root
    root="$(cd "$script_dir/../.." && pwd)"
    export TOOLKIT_ROOT="$root"

    # shellcheck disable=SC1091
    . "$root/lib/common.sh"
    # shellcheck disable=SC1091
    . "$root/lib/launch.sh"
    # shellcheck disable=SC1091
    . "$root/lib/tools.sh"

    ensure_user_env >/dev/null 2>&1 || true
    load_user_env >/dev/null 2>&1 || true
    ai_load_env >/dev/null 2>&1 || true
}

# rocm_ai_shim_install <tool-key> — install (or update) a registry tool.
rocm_ai_shim_install() {
    local key="$1"
    local name
    name="$(rocm_ai_tool_name "$key")" || { err "Unknown tool '$key'"; return 1; }

    if ! ai_is_wsl; then
        err "$name requires WSL2 on this toolkit."
        return 1
    fi

    if rocm_ai_tool_installed "$key"; then
        log "$name is already installed — updating it instead."
        rocm_ai_update_tool "$key"
        return $?
    fi

    rocm_ai_install_tool "$key"
}
