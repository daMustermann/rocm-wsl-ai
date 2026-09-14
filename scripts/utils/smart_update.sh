#!/bin/bash
set -euo pipefail

# ===============================================================================
# Smart Update — ROCm WSL AI Toolkit
#
# Scans every installed component, detects what is outdated or behind on
# commits, then lets the user update everything or pick individual items.
#
# Pinned target versions:
#   ROCm   → 7.2.3
#   PyTorch → 2.9.1 + rocm7.2
# ===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/common.sh"
else
    echo "common.sh not found" >&2; exit 1
fi

# ─── Target versions ──────────────────────────────────────────────────────────
TARGET_ROCM="7.2.3"
TARGET_PYTORCH="2.9.1"

# ─── Paths ────────────────────────────────────────────────────────────────────
VENV_PATH="$HOME/genai_env"
COMFYUI_DIR="$HOME/ComfyUI"
SDNEXT_DIR="$HOME/SD.Next"
A1111_DIR="$HOME/stable-diffusion-webui"
KOHYA_DIR="$HOME/kohya_ss"
TEXTGEN_DIR="$HOME/text-generation-webui"

# ─── Scan result parallel arrays ──────────────────────────────────────────────
declare -a R_KEY=()
declare -a R_LABEL=()
declare -a R_CURRENT=()
declare -a R_TARGET=()
declare -a R_STATUS=()    # ok | update | missing | skipped

# ─── Helpers ──────────────────────────────────────────────────────────────────

_ver_lt() {
    # Returns true (0) when $1 is strictly less than $2 (semver sort)
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ] && [ "$1" != "$2" ]
}

_add() {
    R_KEY+=("$1"); R_LABEL+=("$2"); R_CURRENT+=("$3")
    R_TARGET+=("$4"); R_STATUS+=("$5")
}

# ─── Scanners ─────────────────────────────────────────────────────────────────

_scan_rocm() {
    local current=""
    [ -f "/opt/rocm/.info/version" ] && \
        current=$(head -1 /opt/rocm/.info/version 2>/dev/null | tr -cd '0-9.')

    if [ -z "$current" ]; then
        _add "rocm" "ROCm" "not installed" "$TARGET_ROCM" "missing"
    elif _ver_lt "$current" "$TARGET_ROCM"; then
        _add "rocm" "ROCm" "$current" "$TARGET_ROCM" "update"
    else
        _add "rocm" "ROCm" "$current" "$TARGET_ROCM" "ok"
    fi
}

_scan_rocdxg() {
    if [ -f "/opt/rocm/lib/librocdxg.so" ]; then
        _add "rocdxg" "ROCDXG (librocdxg)" "present" "—" "ok"
    else
        _add "rocdxg" "ROCDXG (librocdxg)" "missing" "rebuild needed" "missing"
    fi
}

_scan_pytorch() {
    if [ ! -f "$VENV_PATH/bin/activate" ]; then
        _add "pytorch" "PyTorch (genai_env)" "venv not found" "—" "skipped"
        return
    fi
    local current=""
    current=$(
        # shellcheck disable=SC1090
        source "$VENV_PATH/bin/activate" 2>/dev/null || true
        python3 -c "import torch; print(torch.__version__)" 2>/dev/null || echo ""
    ) || true

    local clean="${current%%+*}"   # "2.7.0+rocm7.2.3..." → "2.7.0"

    if [ -z "$clean" ]; then
        _add "pytorch" "PyTorch (genai_env)" "import failed" "$TARGET_PYTORCH+rocm7.2" "missing"
    elif _ver_lt "$clean" "$TARGET_PYTORCH"; then
        _add "pytorch" "PyTorch (genai_env)" "$current" "$TARGET_PYTORCH+rocm7.2" "update"
    else
        _add "pytorch" "PyTorch (genai_env)" "$current" "$TARGET_PYTORCH+rocm7.2" "ok"
    fi
}

_scan_git_tool() {
    local key="$1" label="$2" dir="$3"
    [ -d "$dir/.git" ] || return 0   # not installed → silently skip

    log "  Fetching $label ..."
    git -C "$dir" fetch origin --quiet 2>/dev/null || true

    local branch
    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    local behind
    behind=$(git -C "$dir" rev-list "HEAD..origin/$branch" --count 2>/dev/null || echo "?")
    local hash
    hash=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "local")

    if [ "$behind" = "?" ]; then
        _add "$key" "$label" "$hash" "fetch failed — update recommended" "update"
    elif [ "$behind" -eq 0 ]; then
        _add "$key" "$label" "$hash (latest)" "—" "ok"
    else
        _add "$key" "$label" "$hash" "$behind commit(s) behind" "update"
    fi
}

_scan_ollama() {
    command -v ollama >/dev/null 2>&1 || return 0

    local current=""
    current=$(ollama --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")

    # Try GitHub API (non-fatal, 5-second timeout)
    local latest=""
    latest=$(curl -fsSL --max-time 5 \
        "https://api.github.com/repos/ollama/ollama/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || latest=""

    if [ -n "$latest" ] && [ "$current" != "unknown" ] && _ver_lt "$current" "$latest"; then
        _add "ollama" "Ollama" "$current" "$latest" "update"
    elif [ -z "$latest" ]; then
        _add "ollama" "Ollama" "$current" "latest (offline check)" "update"
    else
        _add "ollama" "Ollama" "$current" "$latest" "ok"
    fi
}

# ─── Display ──────────────────────────────────────────────────────────────────

_print_table() {
    echo ""
    if command -v gum >/dev/null 2>&1; then
        printf "  %s  %-24s  %-32s  %-26s  %s\n" \
            " " \
            "$(gum style --bold "Component")" \
            "$(gum style --bold "Installed")" \
            "$(gum style --bold "Target / Status")" \
            "$(gum style --bold "Result")"
        printf "  %s\n" "$(gum style --foreground 240 "───────────────────────────────────────────────────────────────────────────────────────")"
    else
        printf "  %-6s %-24s %-32s %-26s %s\n" "" "Component" "Installed" "Target / Status" "Result"
        printf "  %s\n" "──────────────────────────────────────────────────────────────────────────────────────"
    fi

    local total=${#R_KEY[@]}
    for ((i=0; i<total; i++)); do
        local color icon status_text
        case "${R_STATUS[$i]}" in
            ok)      color=46;  icon="✔"; status_text="Up to date" ;;
            update)  color=214; icon="↑"; status_text="UPDATE AVAILABLE" ;;
            missing) color=196; icon="✖"; status_text="Not present" ;;
            skipped) color=240; icon="—"; status_text="Skipped" ;;
            *)       color=240; icon="?"; status_text="Unknown" ;;
        esac

        if command -v gum >/dev/null 2>&1; then
            printf "  %s  %-24s  %-32s  %-26s  %s\n" \
                "$(gum style --foreground "$color" "$icon")" \
                "${R_LABEL[$i]}" \
                "$(gum style --foreground 252 "${R_CURRENT[$i]:0:32}")" \
                "$(gum style --foreground "$color" "${R_TARGET[$i]:0:26}")" \
                "$(gum style --foreground "$color" "$status_text")"
        else
            local tag
            case "${R_STATUS[$i]}" in
                ok)      tag="[ OK ]" ;;
                update)  tag="[ !! ]" ;;
                missing) tag="[MISS]" ;;
                *)       tag="[ -- ]" ;;
            esac
            printf "  %s  %-24s  %-32s  %-26s  %s\n" \
                "$tag" "${R_LABEL[$i]}" \
                "${R_CURRENT[$i]:0:32}" "${R_TARGET[$i]:0:26}" "$status_text"
        fi
    done
    echo ""
}

# ─── Collect keys with status=update ─────────────────────────────────────────

_collect_updates() {
    local -n _out_ref=$1
    local total=${#R_KEY[@]}
    for ((i=0; i<total; i++)); do
        [ "${R_STATUS[$i]}" = "update" ] && _out_ref+=("${R_KEY[$i]}")
    done
}

# ─── Load update functions from update_ai_setup.sh ────────────────────────────

_load_update_fns() {
    local f="$SCRIPT_DIR/scripts/utils/update_ai_setup.sh"
    if [ ! -f "$f" ]; then
        err "update_ai_setup.sh not found: $f"; exit 1
    fi
    # SMART_UPDATE_SOURCED=1 prevents the script from launching its own menu
    SMART_UPDATE_SOURCED=1 source "$f" 2>/dev/null || true
}

# ─── Execute a single update by key ───────────────────────────────────────────

_run_update() {
    local key="$1"
    case "$key" in
        rocm)
            update_rocm
            ;;
        rocdxg)
            warn "ROCDXG requires a full rebuild via the upgrade script."
            if confirm "Launch scripts/install/upgrade_to_rocdxg.sh now?"; then
                "$SCRIPT_DIR/scripts/install/upgrade_to_rocdxg.sh" || true
            fi
            ;;
        pytorch)       update_pytorch ;;
        comfyui)       update_comfyui ;;
        sdnext)        update_sdnext ;;
        automatic1111) update_automatic1111 ;;
        kohya_ss)      update_kohya_ss ;;
        textgen)       update_textgen ;;
        ollama)        update_ollama ;;
        *)             warn "Unknown component key '$key' — skipping" ;;
    esac
}

# ─── Main ─────────────────────────────────────────────────────────────────────

_header() {
    clear; echo ""
    if command -v gum >/dev/null 2>&1; then
        gum style --bold --foreground 212 --border normal --border-foreground 212 \
            --padding "0 2" "🤖 Smart Update — ROCm WSL AI Toolkit"
    else
        echo "=== Smart Update — ROCm WSL AI Toolkit ==="
    fi
    echo ""
}

main() {
    _header

    # ── Phase 1: Scan ──────────────────────────────────────────────────────
    log "Scanning all components (fetching git remotes — may take a few seconds) ..."
    echo ""
    _scan_rocm
    _scan_rocdxg
    _scan_pytorch
    _scan_git_tool "comfyui"       "ComfyUI"       "$COMFYUI_DIR"
    _scan_git_tool "sdnext"        "SD.Next"       "$SDNEXT_DIR"
    _scan_git_tool "automatic1111" "Automatic1111" "$A1111_DIR"
    _scan_git_tool "kohya_ss"      "kohya_ss"      "$KOHYA_DIR"
    _scan_git_tool "textgen"       "TextGen WebUI" "$TEXTGEN_DIR"
    _scan_ollama

    # ── Phase 2: Display results ───────────────────────────────────────────
    _header
    log "Scan complete. Results:"
    _print_table

    # ── Phase 3: Anything to do? ───────────────────────────────────────────
    declare -a needs_update=()
    _collect_updates needs_update

    if [ ${#needs_update[@]} -eq 0 ]; then
        success "Everything is up to date — nothing to do!"
        echo ""
        read -rp "  Press Enter to return..."
        return
    fi

    warn "${#needs_update[@]} component(s) can be updated."
    echo ""

    # ── Phase 4: User choice ───────────────────────────────────────────────
    declare -a selected=()

    if command -v gum >/dev/null 2>&1; then
        local mode
        mode=$(gum choose --cursor="» " \
            --header="How do you want to proceed?" \
            "all  — Update all ${#needs_update[@]} component(s) listed above" \
            "pick — Choose individual components" \
            "q    — Cancel") || mode="q"

        case "$mode" in
            q*) log "Cancelled."; echo ""; read -rp "  Press Enter..."; return ;;
            pick*)
                # Build display options for gum choose --no-limit
                local -a opts=()
                for k in "${needs_update[@]}"; do
                    for ((i=0; i<${#R_KEY[@]}; i++)); do
                        if [ "${R_KEY[$i]}" = "$k" ]; then
                            opts+=("$k — ${R_LABEL[$i]}  (${R_CURRENT[$i]}  →  ${R_TARGET[$i]})")
                            break
                        fi
                    done
                done
                local picks
                picks=$(printf '%s\n' "${opts[@]}" | \
                    gum choose --no-limit --cursor="» " \
                    --header="Select components to update (Tab = toggle, Enter = confirm):") || picks=""
                while IFS= read -r line; do
                    [ -z "$line" ] && continue
                    selected+=("${line%% *}")  # extract key (first word before " — ")
                done <<< "$picks"
                ;;
            all*)
                selected=("${needs_update[@]}")
                ;;
        esac
    else
        # Plain-text fallback
        echo "  a) Update all"
        echo "  p) Pick individual components"
        echo "  q) Cancel"
        read -rp "  Choice: " raw
        case "$raw" in
            q|Q) return ;;
            p|P)
                echo ""
                local idx=1
                for k in "${needs_update[@]}"; do
                    for ((i=0; i<${#R_KEY[@]}; i++)); do
                        if [ "${R_KEY[$i]}" = "$k" ]; then
                            printf "  %2d) %-22s %s → %s\n" \
                                "$idx" "${R_LABEL[$i]}" "${R_CURRENT[$i]}" "${R_TARGET[$i]}"
                            break
                        fi
                    done
                    ((idx++))
                done
                echo ""
                read -rp "  Enter numbers separated by spaces: " nums
                for n in $nums; do
                    local sk="${needs_update[$((n-1))]:-}"
                    [ -n "$sk" ] && selected+=("$sk")
                done
                ;;
            *) selected=("${needs_update[@]}") ;;
        esac
    fi

    if [ ${#selected[@]} -eq 0 ]; then
        log "Nothing selected."
        echo ""
        read -rp "  Press Enter to return..."
        return
    fi

    # ── Phase 5: Execute updates ───────────────────────────────────────────
    _load_update_fns

    echo ""
    log "Starting update of ${#selected[@]} component(s): ${selected[*]}"
    echo ""

    for key in "${selected[@]}"; do
        _run_update "$key"
        echo ""
    done

    success "Smart update finished!"
    echo ""

    if command -v gum >/dev/null 2>&1; then
        if confirm "Run a fresh scan to verify?"; then
            # Reset arrays and re-scan
            R_KEY=(); R_LABEL=(); R_CURRENT=(); R_TARGET=(); R_STATUS=()
            needs_update=(); selected=()
            _header
            log "Re-scanning ..."
            _scan_rocm; _scan_rocdxg; _scan_pytorch
            _scan_git_tool "comfyui"       "ComfyUI"       "$COMFYUI_DIR"
            _scan_git_tool "sdnext"        "SD.Next"       "$SDNEXT_DIR"
            _scan_git_tool "automatic1111" "Automatic1111" "$A1111_DIR"
            _scan_git_tool "kohya_ss"      "kohya_ss"      "$KOHYA_DIR"
            _scan_git_tool "textgen"       "TextGen WebUI" "$TEXTGEN_DIR"
            _scan_ollama
            _header
            log "Post-update status:"
            _print_table
        fi
    fi

    read -rp "  Press Enter to return..."
}

main "$@"
