#!/bin/bash
# ==============================================================================
# First-run welcome wizard
# ==============================================================================
# Sourced by menu.sh — do not execute directly. Defines first_run_check().
# Shown once, on a genuinely fresh install, then never again.
# ==============================================================================

FIRST_RUN_MARKER="${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}/.first_run_done"

first_run_check() {
    [ -f "$FIRST_RUN_MARKER" ] && return 0

    ensure_user_env >/dev/null 2>&1 || true
    mkdir -p "$(dirname "$FIRST_RUN_MARKER")" 2>/dev/null || true

    clear
    printf '\n'

    if command -v gum >/dev/null 2>&1; then
        gum style \
            --border double --margin "1 2" --padding "1 3" \
            --border-foreground 212 --align center \
            "$(gum style --bold --foreground 212 "Welcome to the ROCm WSL2 AI Toolkit")" \
            "$(gum style --foreground 240 "v${ROCM_AI_VERSION}")"
        printf '\n'
        gum style --border rounded --margin "0 2" --padding "1 2" --border-foreground 63 \
"$(gum style --bold --foreground 63 'Setup takes about 20 minutes and three steps')

  $(gum style --foreground 46 '1.') $(gum style --bold 'Quick start')
     Installs ROCm + PyTorch into an isolated environment.
     Takes 10-20 minutes.

  $(gum style --foreground 46 '2.') $(gum style --bold 'Restart WSL2')
     In Windows PowerShell:  $(gum style --foreground 212 'wsl --shutdown')
     Then reopen Ubuntu and run ./menu.sh again.
     $(gum style --foreground 214 'This step is required — without it your GPU is invisible.')

  $(gum style --foreground 46 '3.') $(gum style --bold 'Quick start again')
     It continues with an AI tool (ComfyUI recommended) and tunes
     your GPU automatically.

$(gum style --foreground 240 'Before step 1, Windows needs the AMD Adrenalin 26.2.2+ driver')
$(gum style --foreground 240 'and the Windows SDK. Settings -> GPU diagnostics checks both.')"

        printf '\n'
        gum style --foreground 240 --margin "0 2" \
            "Your settings live in: $(gum style --foreground 212 "~/.config/rocm-wsl-ai/user.env")"
        gum style --foreground 240 --margin "0 2" \
            "Change them later via: Settings in the main menu"
    else
        printf '==========================================\n'
        printf '  ROCm WSL2 AI Toolkit  v%s\n' "$ROCM_AI_VERSION"
        printf '==========================================\n\n'
        printf 'Setup takes about 20 minutes and three steps:\n\n'
        printf '  1. Quick start     installs ROCm + PyTorch (10-20 min)\n'
        printf '  2. Restart WSL2    in PowerShell: wsl --shutdown\n'
        printf '                     then reopen Ubuntu and run ./menu.sh\n'
        printf '                     (required — without it your GPU is invisible)\n'
        printf '  3. Quick start     continues with an AI tool and tuning\n\n'
        printf 'Before step 1, Windows needs the AMD Adrenalin 26.2.2+ driver\n'
        printf 'and the Windows SDK. Settings -> GPU diagnostics checks both.\n\n'
        printf 'Settings: %s\n' "$USER_ENV"
    fi

    printf '\n'
    read -rp "  Press Enter to continue to the menu..."
    touch "$FIRST_RUN_MARKER"
}
