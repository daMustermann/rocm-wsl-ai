#!/bin/bash
# ==============================================================================
# ROCm WSL2 AI Toolkit — Main Menu
# ==============================================================================
# Design goals, in order:
#
#   1. Tell the user what to do next, not present a wall of options. The home
#      screen computes the single most useful next action from the state of the
#      machine and offers it first.
#   2. Never dead-end. Every menu can be escaped, and an unknown selection
#      returns to the previous menu instead of silently doing nothing.
#   3. Never lie. Status lines reflect what was actually detected, and anything
#      that could not be determined says so rather than showing a guess.
#   4. Stay fast. Startup does no GPU probing; that is lazy and cached.
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TOOLKIT_ROOT="$SCRIPT_DIR"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/version.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/migrate.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/launch.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/tools.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"

# Optional components; the menu degrades if any are missing.
[ -f "$SCRIPT_DIR/scripts/utils/gpu_diag.sh" ] && . "$SCRIPT_DIR/scripts/utils/gpu_diag.sh"
[ -f "$SCRIPT_DIR/scripts/utils/first_run.sh" ] && . "$SCRIPT_DIR/scripts/utils/first_run.sh"

PERF_ENGINE="$SCRIPT_DIR/scripts/utils/perf_engine.py"

mkdir -p "$ROCM_AI_CONFIG_DIR" 2>/dev/null || true
ensure_user_env >/dev/null 2>&1 || true
load_user_env >/dev/null 2>&1 || true

# Make sure every script is executable (a fresh clone on Windows often is not).
find "$SCRIPT_DIR/scripts" -type f -name "*.sh" -not -executable -exec chmod +x {} + 2>/dev/null || true
chmod +x "$SCRIPT_DIR/menu.sh" 2>/dev/null || true

# Shorthand used throughout this file.
venv_python() { rocm_ai_venv_python; }

# ==============================================================================
# Quick start
# ==============================================================================

quick_start() {
    local base_ok="no"
    [ -f "$HOME/genai_env/bin/activate" ] && base_ok="yes"

    clear
    ai_banner "Quick start"

    if [ "$base_ok" = "no" ]; then
        cat <<'EOF'
  This will set everything up in one go:

    1. Install ROCm + PyTorch into an isolated environment   (10-20 minutes)
    2. You restart WSL2, as Windows requires for GPU access
    3. Come back and choose "Quick start" again

  Before starting, make sure Windows has:
    - AMD Adrenalin driver 26.2.2 or newer
    - The Windows SDK installed
  Both are checked in Settings -> GPU diagnostics.
EOF
        printf '\n'
        if ! confirm "Install the base environment now?"; then
            return 0
        fi
        install_base
        return 0
    fi

    if ! ai_preflight; then
        printf '\n'
        ai_warn "The GPU is not usable yet, so setup cannot finish."
        ai_say  "     Fix the items above, then run Quick start again."
        printf '\n'
        read -rp "  Press Enter to return..."
        return 0
    fi

    local installed
    installed="$(installed_tool_count)"

    if [ "$installed" = "0" ]; then
        printf '\n'
        ai_info "No AI tools installed yet."
        if confirm "Install ComfyUI (recommended) now?"; then
            rocm_ai_install_tool "comfyui"
            printf '\n'
            if confirm "Create a Windows desktop shortcut for ComfyUI?"; then
                rocm_ai_create_shortcut "comfyui"
            fi
        fi
    fi

    printf '\n'
    ai_info "Checking performance tuning."
    if [ "$(perf_profile_label)" = "not tuned" ]; then
        if confirm "Run the GPU tuner now? (2-5 minutes, one time)"; then
            bash "$SCRIPT_DIR/scripts/utils/auto_tuner.sh"
        fi
    else
        ai_ok "Already tuned (profile: $(perf_profile_label))."
    fi

    printf '\n'
    ai_ok "Quick start complete."
    local port
    port="$(rocm_ai_tool_effective_port comfyui)"
    if rocm_ai_tool_installed comfyui; then
        ai_say "     Launch ComfyUI from the main menu, then open http://localhost:$port"
    fi
    printf '\n'
    read -rp "  Press Enter to return..."
}

# ==============================================================================
# Install
# ==============================================================================

install_base() {
    headline "Base environment"
    if ! is_wsl; then
        msgbox "WSL2 required" "This toolkit targets WSL2. On native Linux, use AMD's official ROCm docs."
        return 1
    fi
    if ! yesno "Install ROCm 7.2.3 + ROCDXG + PyTorch" \
        "This will:\n\
 • Install AMD ROCm 7.2.3 from AMD's official repository\n\
 • Build and install ROCDXG (librocdxg), the WSL GPU bridge\n\
 • Create an isolated Python environment in ~/genai_env\n\
 • Install PyTorch 2.9.1 with ROCm support\n\n\
 Requires on Windows:\n\
 • AMD Adrenalin 26.2.2 or newer\n\
 • Windows SDK (needed to build ROCDXG)\n\n\
 Takes 10-20 minutes. Afterwards you must restart WSL2."; then
        return 0
    fi

    bash "$SCRIPT_DIR/scripts/install/setup_pytorch_rocm.sh"
    local rc=$?

    if [ "$rc" -eq 0 ]; then
        rm -f "$ROCM_AI_PREFLIGHT_CACHE"
        msgbox "Base environment installed" \
"Next step — this one matters:

  1. Close this terminal
  2. In Windows PowerShell or CMD, run:

         wsl --shutdown

  3. Reopen Ubuntu and run ./menu.sh again

That restart is what lets your user join the render/video groups and
activates the DXCore GPU bridge. Without it, PyTorch cannot see the GPU."
    fi
    return $rc
}

install_menu() {
    while true; do
        render_home >/dev/null 2>&1
        local -a options=()
        local base_ok="no"
        [ -f "$HOME/genai_env/bin/activate" ] && base_ok="yes"

        if [ "$base_ok" = "no" ]; then
            options+=("base|Base environment — ROCm + PyTorch  (do this first)")
        else
            options+=("repair|Repair / reinstall the base environment")
        fi
        options+=("upgrade|Upgrade from an older ROCm to 7.2.3 + ROCDXG")

        local key name
        for key in $(rocm_ai_all_tool_keys); do
            name="$(rocm_ai_tool_name "$key")" || continue
            if rocm_ai_tool_installed "$key"; then
                options+=("tool:$key|$name  (installed)")
            else
                options+=("tool:$key|$name")
            fi
        done
        options+=("add|Add a third-party tool from any git repository")
        options+=("back|Back")

        local choice
        choice="$(choose "Install — what would you like to install?" "${options[@]}")" || return 0
        local action="${choice%%|*}"

        case "$action" in
            base|repair) install_base ;;
            upgrade)
                if [ -f "$SCRIPT_DIR/scripts/install/upgrade_to_rocdxg.sh" ]; then
                    bash "$SCRIPT_DIR/scripts/install/upgrade_to_rocdxg.sh"
                else
                    msgbox "Missing" "upgrade_to_rocdxg.sh not found."
                fi
                ;;
            add) rocm_ai_add_custom_tool; printf '\n'; read -rp "  Press Enter to continue..." ;;
            tool:*)
                local tkey="${action#tool:}"
                local tname; tname="$(rocm_ai_tool_name "$tkey")"
                rocm_ai_install_tool "$tkey"
                printf '\n'
                if rocm_ai_tool_installed "$tkey" \
                    && confirm "Create a Windows desktop shortcut for $tname?"; then
                    rocm_ai_create_shortcut "$tkey"
                fi
                printf '\n'
                read -rp "  Press Enter to continue..."
                ;;
            back|*) return 0 ;;
        esac
    done
}

# ==============================================================================
# Launch
# ==============================================================================

launch_menu() {
    while true; do
        local -a options=()
        local key name suffix
        for key in $(rocm_ai_all_tool_keys); do
            rocm_ai_tool_installed "$key" || continue
            name="$(rocm_ai_tool_name "$key")"
            if tool_running "$key"; then
                suffix="  (already running on port $(rocm_ai_tool_effective_port "$key"))"
            else
                suffix=""
            fi
            options+=("launch:$key|$name$suffix")
        done

        if [ "${#options[@]}" -eq 0 ]; then
            msgbox "Nothing to launch" "No AI tools are installed yet.\n\nInstall one first:\nMain menu -> Install tools -> ComfyUI (recommended)"
            return 0
        fi

        options+=("stopped|Stop all AI servers and free VRAM")
        options+=("back|Back")

        local choice
        choice="$(choose "Launch — choose a tool" "${options[@]}")" || return 0
        local action="${choice%%|*}"

        case "$action" in
            launch:*)
                local tkey="${action#launch:}"
                if tool_running "$tkey"; then
                    local port; port="$(rocm_ai_tool_effective_port "$tkey")"
                    printf '\n'
                    ai_info "$(rocm_ai_tool_name "$tkey") is already running."
                    ai_say  "     Open:  http://localhost:$port"
                    printf '\n'
                    read -rp "  Press Enter to continue..."
                    continue
                fi
                rocm_ai_launch_tool "$tkey"
                printf '\n'
                read -rp "  Press Enter to return to the menu..."
                ;;
            stopped) stop_all_servers ;;
            back|*) return 0 ;;
        esac
    done
}

# Release VRAM by stopping whatever the toolkit started. This is the answer to
# "Python is holding my GPU hostage and my games are stuttering".
stop_all_servers() {
    clear
    ai_banner "Stop all AI servers"

    local found=0 key port pid name
    local -a victims_pid=() victims_name=()

    for key in $(rocm_ai_all_tool_keys); do
        port="$(rocm_ai_tool_effective_port "$key")"
        [ "$port" = "-" ] && continue
        pid="$(ai_port_pid "$port")"
        if [ -n "$pid" ]; then
            name="$(rocm_ai_tool_name "$key")"
            printf '   %-22s port %-6s pid %s\n' "$name" "$port" "$pid"
            victims_pid+=("$pid")
            victims_name+=("$name")
            found=1
        fi
    done

    if [ "$found" = "0" ]; then
        printf '\n'
        ai_ok "Nothing is running. VRAM is already free."
        printf '\n'
        read -rp "  Press Enter to return..."
        return 0
    fi

    printf '\n'
    if ! confirm "Stop these ${#victims_pid[@]} server(s) and release VRAM?"; then
        return 0
    fi

    local i
    for i in "${!victims_pid[@]}"; do
        pid="${victims_pid[$i]}"
        printf '   Stopping %s (pid %s) ... ' "${victims_name[$i]}" "$pid"
        kill -INT "$pid" 2>/dev/null || true
        local waited=0
        while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 20 ]; do
            sleep 0.5
            waited=$((waited + 1))
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
            printf 'forced\n'
        else
            printf 'stopped\n'
        fi
    done

    printf '\n'
    ai_ok "VRAM released back to Windows."
    printf '\n'
    read -rp "  Press Enter to return..."
}

# ==============================================================================
# Performance
# ==============================================================================

performance_menu() {
    while true; do
        local profile; profile="$(perf_profile_label)"
        local choice
        choice="$(choose "Performance   (current tuning: $profile)" \
            "tune|Auto-tune for this GPU  (measures, then applies the winner)" \
            "show|Show the active profile and what it changed" \
            "compare|Show the last benchmark report in detail" \
            "reset|Reset tuning back to ComfyUI defaults" \
            "back|Back")" || return 0

        case "${choice%%|*}" in
            tune)
                bash "$SCRIPT_DIR/scripts/utils/auto_tuner.sh"
                ;;
            show)
                clear
                ai_banner "Active performance profile"
                printf '\n'
                "$(venv_python)" "$PERF_ENGINE" show 2>&1 | sed 's/^/  /'
                printf '\n'
                read -rp "  Press Enter to continue..."
                ;;
            compare)
                clear
                ai_banner "Last benchmark report"
                printf '\n'
                if [ -f "$ROCM_AI_CONFIG_DIR/last_benchmark.json" ]; then
                    if command -v gum >/dev/null 2>&1; then
                        gum pager < "$ROCM_AI_CONFIG_DIR/last_benchmark.json"
                    else
                        less "$ROCM_AI_CONFIG_DIR/last_benchmark.json" 2>/dev/null \
                            || cat "$ROCM_AI_CONFIG_DIR/last_benchmark.json"
                    fi
                else
                    ai_warn "No benchmark has been run yet."
                    printf '\n'
                    read -rp "  Press Enter to continue..."
                fi
                ;;
            reset)
                if confirm "Reset tuning to ComfyUI defaults?"; then
                    "$(venv_python)" "$PERF_ENGINE" apply --profile baseline >/dev/null 2>&1
                    ai_ok "Tuning reset to ComfyUI defaults."
                    printf '\n'
                    read -rp "  Press Enter to continue..."
                fi
                ;;
            back|*) return 0 ;;
        esac
    done
}

# ==============================================================================
# Shortcuts
# ==============================================================================

shortcuts_menu() {
    local -a options=()
    local key name
    for key in $(rocm_ai_all_tool_keys); do
        rocm_ai_tool_installed "$key" || continue
        name="$(rocm_ai_tool_name "$key")"
        options+=("shortcut:$key|$name")
    done

    if [ "${#options[@]}" -eq 0 ]; then
        msgbox "Nothing to add" "Install an AI tool first, then you can put it on your desktop."
        return 0
    fi

    options+=("back|Back")
    local choice
    choice="$(choose "Create a Windows desktop shortcut for:" "${options[@]}")" || return 0
    case "${choice%%|*}" in
        shortcut:*) rocm_ai_create_shortcut "${choice#shortcut:}" ;;
        *) return 0 ;;
    esac
    printf '\n'
    read -rp "  Press Enter to continue..."
}

# ==============================================================================
# Updates
# ==============================================================================

# One line summarising what an upgrade would change, computed without touching
# anything. Shown in the menu so the user knows before committing.
upgrade_status_line() {
    local py="${HOME}/genai_env/bin/python3"
    local pytag codename
    codename="$(va_ubuntu_codename)"
    pytag="$(va_python_tag "$py" 2>/dev/null || va_python_tag python3)"

    local rocm_now rocm_new torch_now
    rocm_now="$(va_rocm_installed 2>/dev/null || true)"
    torch_now="$(va_torch_installed "$py" 2>/dev/null || true)"
    rocm_new="$(va_latest_rocm "$codename" 2>/dev/null || true)"

    if [ -z "$rocm_now" ]; then
        printf 'ROCm not installed — run the upgrade to set it up'
        return 0
    fi
    if [ -n "$rocm_new" ] && va_lt "$rocm_now" "$rocm_new"; then
        printf 'ROCm %s -> %s available' "$rocm_now" "$rocm_new"
        [ -n "$torch_now" ] && printf ' (PyTorch %s installed)' "${torch_now%%+*}"
        return 0
    fi
    if rocm_ai_migration_needed; then
        printf 'Settings need migrating for v4 — run the upgrade'
        return 0
    fi
    printf 'Everything up to date (ROCm %s)' "$rocm_now"
}

updates_menu() {
    while true; do
        local status
        status="$(upgrade_status_line)"

        local choice
        choice="$(choose "Updates   ($status)" \
            "auto|Upgrade everything automatically  (recommended)" \
            "check|Check what would change  (changes nothing)" \
            "toolkit|Update only the toolkit  (git pull)" \
            "tools|Update one AI tool" \
            "smart|Smart update — scan tools, update what is out of date" \
            "back|Back")" || return 0

        case "${choice%%|*}" in
            auto)
                if [ -f "$SCRIPT_DIR/upgrade.sh" ]; then
                    bash "$SCRIPT_DIR/upgrade.sh"
                else
                    msgbox "Missing" "upgrade.sh not found in the toolkit root."
                fi
                printf '\n'
                read -rp "  Press Enter to return to the menu..."
                ;;
            check)
                if [ -f "$SCRIPT_DIR/upgrade.sh" ]; then
                    clear
                    bash "$SCRIPT_DIR/upgrade.sh" --check
                fi
                printf '\n'
                read -rp "  Press Enter to continue..."
                ;;
            toolkit) self_update_toolkit ;;
            tools)
                local -a options=()
                local key name
                for key in $(rocm_ai_all_tool_keys); do
                    rocm_ai_tool_installed "$key" || continue
                    name="$(rocm_ai_tool_name "$key")"
                    options+=("update:$key|$name")
                done
                if [ "${#options[@]}" -eq 0 ]; then
                    msgbox "Nothing to update" "No AI tools are installed yet."
                    continue
                fi
                options+=("back|Back")
                local pick
                pick="$(choose "Update which tool?" "${options[@]}")" || continue
                case "${pick%%|*}" in
                    update:*)
                        rocm_ai_update_tool "${pick#update:}"
                        printf '\n'
                        read -rp "  Press Enter to continue..."
                        ;;
                esac
                ;;
            smart)
                if [ -f "$SCRIPT_DIR/scripts/utils/smart_update.sh" ]; then
                    bash "$SCRIPT_DIR/scripts/utils/smart_update.sh"
                else
                    msgbox "Missing" "smart_update.sh not found."
                fi
                ;;
            back|*) return 0 ;;
        esac
    done
}

self_update_toolkit() {
    headline "Update the toolkit"
    if [ ! -d "$SCRIPT_DIR/.git" ]; then
        msgbox "Not a git checkout" "Self-update needs a git clone.\n\nUpdate manually with:\n  git -C '$SCRIPT_DIR' pull"
        return 0
    fi

    log "Fetching from origin..."
    if ! git -C "$SCRIPT_DIR" fetch origin 2>/dev/null; then
        msgbox "Network error" "Could not reach the remote repository."
        return 0
    fi

    local branch behind
    branch="$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
    behind="$(git -C "$SCRIPT_DIR" rev-list "HEAD..origin/$branch" --count 2>/dev/null || echo 0)"

    if [ "$behind" = "0" ]; then
        msgbox "Up to date" "The toolkit is already on the latest version."
        return 0
    fi

    local changelog
    changelog="$(git -C "$SCRIPT_DIR" log "HEAD..origin/$branch" --oneline --no-merges 2>/dev/null | head -15)"

    if yesno "$behind new commit(s) available" "Changes:\n\n$changelog\n\nApply them now?"; then
        if git -C "$SCRIPT_DIR" pull --rebase --autostash; then
            _show_update_changenotes
            msgbox "Updated" "The toolkit has been updated.\n\nRestart it to use the new version:\n  Press Ctrl+C, then run ./menu.sh"
        else
            msgbox "Update failed" "git pull did not complete.\n\nTry by hand:\n  git -C '$SCRIPT_DIR' pull"
        fi
    fi
}

_show_update_changenotes() {
    _rocm_ai_have_gum || return 0
    local cl="$SCRIPT_DIR/CHANGELOG.md"
    [ -f "$cl" ] || return 0
    local notes
    notes="$(awk '/^## \[/{c++; if(c==2) exit} c==1{print}' "$cl")"
    [ -z "$notes" ] && return 0
    printf '\n'
    gum style --bold --foreground 212 --margin "0 2" "What changed:"
    printf '\n'
    printf '%s\n' "$notes" | gum pager --soft-wrap
}

# ==============================================================================
# Settings
# ==============================================================================

settings_menu() {
    while true; do
        local dxg="${HSA_ENABLE_DXG_DETECTION:-1}"
        local gfx="${HSA_OVERRIDE_GFX_VERSION:-auto}"
        local choice
        choice="$(choose "Settings" \
            "ports|Ports  — change which port each tool listens on" \
            "hibernate|Idle hibernation  — currently ${SMART_SLEEP_TIMEOUT:-1800}s (0 = never)" \
            "gpu|GPU override  — currently $gfx (leave auto unless you must)" \
            "edit|Edit the settings file in a text editor" \
            "diag|GPU diagnostics  — full health check" \
            "enginedoctor|Performance engine self-check" \
            "paths|Show where everything lives" \
            "back|Back")" || return 0

        case "${choice%%|*}" in
            ports) settings_ports ;;
            hibernate) settings_hibernation ;;
            gpu) settings_gpu_override ;;
            edit) settings_edit_file ;;
            diag)
                if declare -f run_gpu_diag >/dev/null 2>&1; then
                    run_gpu_diag
                else
                    msgbox "Unavailable" "gpu_diag.sh is missing from this checkout."
                fi
                ;;
            enginedoctor)
                clear
                ai_banner "Performance engine self-check"
                printf '\n'
                "$(venv_python)" "$PERF_ENGINE" doctor 2>&1 | sed 's/^/  /'
                printf '\n'
                read -rp "  Press Enter to continue..."
                ;;
            paths) settings_paths ;;
            back|*) return 0 ;;
        esac
    done
}

settings_ports() {
    while true; do
        local choice
        choice="$(choose "Ports  (blank input keeps the default)" \
            "comfyui|ComfyUI          currently $(rocm_ai_tool_effective_port comfyui)" \
            "sdnext|SD.Next          currently $(rocm_ai_tool_effective_port sdnext)" \
            "automatic1111|Automatic1111    currently $(rocm_ai_tool_effective_port automatic1111)" \
            "kohya|kohya_ss         currently $(rocm_ai_tool_effective_port kohya_ss)" \
            "back|Back")" || return 0

        local key var current newval
        case "${choice%%|*}" in
            comfyui)       key=COMFYUI_PORT; var=COMFYUI_PORT ;;
            sdnext)        key=SDNEXT_PORT;  var=SDNEXT_PORT ;;
            automatic1111) key=A1111_PORT;   var=A1111_PORT ;;
            kohya)         key=KOHYA_PORT;   var=KOHYA_PORT ;;
            *) return 0 ;;
        esac
        current="$(eval printf '%s' "\${$var:-}")"

        if _rocm_ai_have_gum; then
            newval="$(gum input --value "$current" --placeholder "blank = default" \
                --header "$key:")" || continue
        else
            read -rp "  $key [$current]: " newval
        fi
        _update_user_env "$key" "$newval"
        load_user_env >/dev/null 2>&1 || true
        ai_ok "$key saved."
        sleep 1
    done
}

settings_hibernation() {
    local current="${SMART_SLEEP_TIMEOUT:-1800}"
    printf '\n'
    ai_info "Tools are stopped after this much idle time so VRAM goes back to Windows."
    ai_dim  "  Set 0 to keep tools running indefinitely."
    printf '\n'

    local newval
    if _rocm_ai_have_gum; then
        newval="$(gum input --value "$current" --placeholder "seconds, 0 = never" \
            --header "Idle timeout in seconds:")" || return 0
    else
        read -rp "  Idle timeout in seconds [$current]: " newval
    fi

    if ! [[ "$newval" =~ ^[0-9]+$ ]]; then
        ai_err "Please enter a whole number of seconds."
        sleep 2
        return 0
    fi
    if [ "$newval" = "0" ]; then
        _update_user_env "SMART_SLEEP_DISABLE" "1"
        ai_ok "Idle hibernation disabled."
    else
        _update_user_env "SMART_SLEEP_DISABLE" ""
        _update_user_env "SMART_SLEEP_TIMEOUT" "$newval"
        ai_ok "Idle timeout set to ${newval}s."
    fi
    load_user_env >/dev/null 2>&1 || true
    sleep 1
}

settings_gpu_override() {
    printf '\n'
    cat <<'EOF'
  HSA_OVERRIDE_GFX_VERSION forces ROCm to treat your GPU as a different
  architecture.

  With ROCm 7.x and ROCDXG (what this toolkit installs), you should NOT set it.
  DXCore detects the GPU itself, and an override makes the runtime reject the
  device — your GPU disappears from PyTorch entirely.

  Only set this on native Linux, or if AMD support tells you to.
EOF
    printf '\n'
    local current="${HSA_OVERRIDE_GFX_VERSION:-}"
    local newval
    if _rocm_ai_have_gum; then
        newval="$(gum input --value "$current" --placeholder "blank = auto-detect" \
            --header "HSA_OVERRIDE_GFX_VERSION:")" || return 0
    else
        read -rp "  HSA_OVERRIDE_GFX_VERSION [$current]: " newval
    fi
    _update_user_env "HSA_OVERRIDE_GFX_VERSION" "$newval"
    load_user_env >/dev/null 2>&1 || true
    rm -f "$ROCM_AI_PREFLIGHT_CACHE"
    ai_ok "Saved. Restart WSL2 for this to take effect:  wsl --shutdown"
    printf '\n'
    read -rp "  Press Enter to continue..."
}

settings_edit_file() {
    ensure_user_env
    local editor="${EDITOR:-}"
    if [ -z "$editor" ]; then
        for candidate in nano vim vi; do
            command -v "$candidate" >/dev/null 2>&1 && { editor="$candidate"; break; }
        done
    fi
    if [ -z "$editor" ]; then
        msgbox "No editor found" "Install one first:\n  sudo apt install nano\n\nThen reopen: $USER_ENV"
        return 0
    fi
    "$editor" "$USER_ENV"
    load_user_env >/dev/null 2>&1 || true
}

settings_paths() {
    clear
    ai_banner "Where things live"
    printf '\n'
    printf '   %-26s %s\n' "Toolkit"        "$SCRIPT_DIR"
    printf '   %-26s %s\n' "Settings"       "$USER_ENV"
    printf '   %-26s %s\n' "Tuned profile"  "$ROCM_AI_PERF_ENV"
    printf '   %-26s %s\n' "MIOpen cache"   "$ROCM_AI_CONFIG_DIR/miopen"
    printf '   %-26s %s\n' "Logs"           "$ROCM_AI_LOG_DIR"
    printf '\n'
    local key name dir
    for key in $(rocm_ai_all_tool_keys); do
        name="$(rocm_ai_tool_name "$key")"
        dir="$(rocm_ai_tool_dir "$key")"
        if rocm_ai_tool_installed "$key"; then
            printf '   %-26s %s\n' "$name" "$dir"
        fi
    done
    printf '\n'
    read -rp "  Press Enter to continue..."
}

# ==============================================================================
# Help
# ==============================================================================

show_help() {
    if _rocm_ai_have_gum; then
        gum pager --soft-wrap <<EOF
ROCm WSL2 AI Toolkit v${ROCM_AI_VERSION}

WHY THIS EXISTS
  Running AI on an AMD card under Windows is painful: native ROCm support is
  limited, WSL2 is much faster but needs a GPU bridge and exact driver
  versions, and it is easy to leave a process holding all your VRAM.
  This toolkit sets all of that up and keeps it working.

GETTING STARTED
  1. Main menu -> Quick start
     It works out what is missing and does it in order.
  2. If it asks you to restart WSL, do it. In Windows PowerShell:
         wsl --shutdown
     That restart is required for GPU access to work.
  3. Launch a tool, then open the address it prints in your Windows browser.

MAKING IT FASTER
  Main menu -> Performance -> Auto-tune for this GPU

  This measures several configurations on your actual hardware and keeps the
  one that wins. It takes 2-5 minutes, once. It is honest about the result: if
  nothing beats the stock settings it says so instead of inventing a win.

  Do not run games or other GPU work while it measures.

FREEING VRAM
  Main menu -> Launch -> Stop all AI servers and free VRAM

  Tools also stop themselves after 30 minutes idle. If you close the browser
  and come back later, opening the address again wakes them up.

COMMAND LINE
  ./menu.sh                                  interactive menu
  scripts/utils/perf_engine.py probe         what does this machine support?
  scripts/utils/perf_engine.py bench         measure and tune
  scripts/utils/perf_engine.py show          what tuning is active
  scripts/utils/perf_engine.py doctor        self-check
  scripts/start/comfyui.sh                   launch a tool directly
  scripts/utils/gpu_diag.sh                  full diagnostics

REQUIREMENTS
  Windows 11, WSL2 with Ubuntu 22.04 or 24.04
  AMD Radeon RX 7000 or 9000 series, or Ryzen Strix / Strix Halo
  AMD Adrenalin driver 26.2.2 or newer
  Windows SDK (used to build the ROCDXG GPU bridge)

DOCUMENTATION
  README.md                    overview and quick start
  docs/PERFORMANCE.md          what the tuner measures and why
  docs/TROUBLESHOOTING.md      when things go wrong
  docs/ADDING_TOOLS.md         registering your own tools
  docs/ARCHITECTURE.md         how the pieces fit together

CREDITS
  ROCm and driver support by AMD.
  PyTorch ROCm integration by the PyTorch team.
  ComfyUI, SD.Next, Automatic1111, kohya_ss and Text Generation WebUI are
  separate projects, each with its own licence and maintainers.
EOF
    else
        sed -n '1,120p' "$SCRIPT_DIR/README.md"
        printf '\n'
        read -rp "  Press Enter to continue..."
    fi
}

# ==============================================================================
# Main loop
# ==============================================================================

main_menu() {
    while true; do
        render_home

        # Keep the toolbar stable so muscle memory works.
        local choice
        choice="$(choose "What next?" \
            "quick|Quick start          — set up or finish setting up" \
            "install|Install             — base environment and AI tools" \
            "launch|Launch              — start a tool, or free VRAM" \
            "perf|Performance         — auto-tune this GPU" \
            "shortcut|Desktop shortcut    — put a tool on your Windows desktop" \
            "updates|Updates             — toolkit and tools" \
            "settings|Settings            — ports, diagnostics, files" \
            "help|Help")" || { clear; exit 0; }

        case "${choice%%|*}" in
            quick)    quick_start ;;
            install)  install_menu ;;
            launch)   launch_menu ;;
            perf)     performance_menu ;;
            shortcut) shortcuts_menu ;;
            updates)  updates_menu ;;
            settings) settings_menu ;;
            help)     show_help ;;
            *)        clear; exit 0 ;;
        esac
    done
}

# ==============================================================================
# Startup
# ==============================================================================

check_gum() {
    command -v gum >/dev/null 2>&1 && return 0

    printf '\n'
    printf '  This menu looks much better with %bgum%b, and installs it in one step.\n' "$BOLD" "$NC"
    printf '  Without it the toolkit still works, using a plain text menu.\n'
    printf '\n'
    if confirm "Install gum now?"; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo mkdir -p /etc/apt/keyrings
            if curl -fsSL https://repo.charm.sh/apt/gpg.key \
                | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null; then
                printf 'deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *\n' \
                    | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
                sudo apt-get update -y >/dev/null 2>&1
                sudo apt-get install -y gum >/dev/null 2>&1 || true
            fi
        fi
    fi

    if command -v gum >/dev/null 2>&1; then
        success "gum installed."
    else
        warn "Continuing without gum — using the plain text menu."
    fi
    return 0
}

# ==============================================================================
# Startup
# ==============================================================================
# Only run any of the below when menu.sh is executed directly. Sourcing it (as
# tests and other front-ends do) loads the libraries without launching a menu
# and without blocking on a prompt.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    check_gum

    # One-time welcome, only on a genuinely fresh install.
    if declare -f first_run_check >/dev/null 2>&1; then
        first_run_check 2>/dev/null || true
    fi

    # Warn about the (rare) leftover variable that would crash every launch.
    if [ -n "${PYTORCH_HIP_ALLOC_CONF:-}" ]; then
        clear
        err "PYTORCH_HIP_ALLOC_CONF is set in your environment."
        ai_say "     That variable crashes PyTorch 2.9.1+rocm7.2.3 on import."
        ai_say "     The toolkit will ignore it, but other Python programs will not."
        ai_say "     Remove it from ~/.bashrc, ~/.profile, or:"
        ai_say "       $USER_ENV"
        printf '\n'
        read -rp "  Press Enter to continue..."
    fi

    main_menu
fi
