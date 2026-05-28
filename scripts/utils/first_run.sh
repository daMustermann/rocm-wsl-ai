#!/bin/bash
# First-run welcome wizard for ROCm WSL AI Toolkit
# This file is sourced by menu.sh — do NOT execute directly.
# Defines: first_run_check()

FIRST_RUN_MARKER="${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}/.first_run_done"

first_run_check() {
    [ -f "$FIRST_RUN_MARKER" ] && return 0

    # Initialise user.env with defaults (from common.sh)
    ensure_user_env
    mkdir -p "$(dirname "$FIRST_RUN_MARKER")"

    clear
    echo ""

    if command -v gum >/dev/null 2>&1; then
        gum style \
            --border double --margin "1 2" --padding "1 3" \
            --border-foreground 212 --align center \
            "$(gum style --bold --foreground 212 "👋 Welcome to ROCm WSL2 AI Toolkit v3.2.0")" \
            "$(gum style --foreground 240 "First run detected  —  here is how to get started:")"
        echo ""

        gum style --border rounded --margin "0 2" --padding "1 2" --border-foreground 63 \
"$(gum style --bold --foreground 63 "🚀 Quick Start — 4 Steps")

  $(gum style --foreground 46 '➊') $(gum style --bold 'Install Tools  →  Base Environment')
     Installs ROCm 7.2.3 + PyTorch 2.9.1  (takes 10 – 20 min)

  $(gum style --foreground 46 '➋') $(gum style --bold 'Restart WSL2') after the base install:
     Open PowerShell on Windows and run:
     $(gum style --foreground 212 'wsl --shutdown')  then relaunch Ubuntu

  $(gum style --foreground 46 '➌') $(gum style --bold 'Install an AI tool')  →  ComfyUI recommended
     Then launch it from the Launch Tool menu.

  $(gum style --foreground 46 '➍') Open your browser at:
     $(gum style --foreground 212 'http://localhost:8188')

$(gum style --foreground 240 "  💡 Magic Settings Auto-Tuner finds the fastest GPU settings for your card.")
$(gum style --foreground 240 "  💡 Create Desktop Shortcuts for 1-click launch directly from Windows.")
$(gum style --foreground 240 "  💡 Settings → GPU-Profile to fix GPU detection issues.")
$(gum style --foreground 240 "  💡 Settings → GPU Diagnostics if something is not working.")"

        echo ""
        gum style --foreground 240 --margin "0 2" \
            "Persistent settings are stored in: $(gum style --foreground 212 "~/.config/rocm-wsl-ai/user.env")"
        gum style --foreground 240 --margin "0 2" \
            "Edit them anytime via: Main Menu → ⚙️ Settings → Edit Settings"
    else
        echo "==========================="
        echo " ROCm WSL AI Toolkit v3.2.0"
        echo "==========================="
        echo ""
        echo "First run — Quick Start:"
        echo "  1. Install Tools → Base Environment"
        echo "  2. wsl --shutdown  (in PowerShell), then restart Ubuntu"
        echo "  3. Install an AI tool  (e.g. ComfyUI)"
        echo "  4. Launch Tool → open http://localhost:8188 in your browser"
        echo ""
        echo "Settings are stored in: $USER_ENV"
    fi

    echo ""
    read -rp "  Press Enter to continue to the main menu..."
    touch "$FIRST_RUN_MARKER"
}
