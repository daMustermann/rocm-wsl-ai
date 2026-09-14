#!/usr/bin/env bash
# ==============================================================================
# ROCm WSL2 AI Toolkit — one-line installer
# ==============================================================================
#   curl -fsSL https://raw.githubusercontent.com/daMustermann/rocm-wsl-ai/main/install.sh | bash
#
# Or, without piping anything into a shell (recommended if you like to read what
# you run first):
#
#   git clone https://github.com/daMustermann/rocm-wsl-ai.git
#   cd rocm-wsl-ai && ./install.sh
#
# This script only prepares the toolkit: it checks the environment, installs the
# terminal UI dependency, and hands over to the menu. It does NOT install ROCm or
# PyTorch — those are large, need sudo, and need you to be watching, so they stay
# behind an explicit choice in the menu.
# ==============================================================================
set -uo pipefail

REPO_URL="${ROCM_AI_REPO:-https://github.com/daMustermann/rocm-wsl-ai.git}"
INSTALL_DIR="${ROCM_AI_DIR:-$HOME/rocm-wsl-ai}"

BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
GREEN=$'\033[38;5;46m'; YELLOW=$'\033[38;5;214m'; RED=$'\033[38;5;196m'
ACCENT=$'\033[38;5;212m'

say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✔%s  %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s⚠%s  %s\n' "$YELLOW" "$RESET" "$*"; }
die()  { printf '%s✖%s  %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
step() { printf '\n%s%s%s\n' "$ACCENT" "$*" "$RESET"; }

printf '\n'
printf '%s   ROCm WSL2 AI Toolkit — installer%s\n' "$BOLD" "$RESET"
printf '%s   High-performance AMD AI on Windows, without the setup pain.%s\n' "$DIM" "$RESET"
printf '\n'

# ------------------------------------------------------------------------------
# 1. Are we where we need to be?
# ------------------------------------------------------------------------------
step "1/4  Checking your environment"

if ! grep -qi microsoft /proc/version 2>/dev/null; then
    warn "This does not look like WSL2."
    say  "     The toolkit is built around the WSL2 GPU bridge (ROCDXG)."
    say  "     On native Linux, use AMD's official ROCm documentation instead."
    say  ""
    if [ -t 0 ]; then
        read -rp "     Continue anyway? (y/N): " reply
        case "$reply" in y|Y) ;; *) die "Stopped." ;; esac
    else
        die "Run this inside WSL2, or clone the repo and use ./menu.sh."
    fi
else
    distro="${WSL_DISTRO_NAME:-unknown}"
    ok "Running under WSL2 (distro: $distro)"
fi

# Ubuntu 22.04 (jammy) and 24.04 (noble) are the supported releases: the AMD
# PyTorch wheels are built against specific CPython versions.
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${VERSION_CODENAME:-unknown}" in
        jammy|noble)
            ok "Ubuntu ${VERSION_ID} (${VERSION_CODENAME}) — supported"
            ;;
        *)
            warn "Ubuntu ${VERSION_ID:-?} (${VERSION_CODENAME:-?}) is not a tested release."
            say  "     Supported: Ubuntu 22.04 (jammy) and 24.04 (noble)."
            say  "     Installation may fail on older AMD wheel availability."
            ;;
    esac
fi

for tool in git curl; do
    command -v "$tool" >/dev/null 2>&1 || die "Missing '$tool'. Install it first:  sudo apt install $tool"
done
ok "git and curl present"

# ------------------------------------------------------------------------------
# 2. Get the toolkit
# ------------------------------------------------------------------------------
step "2/4  Getting the toolkit"

# When run from inside an existing checkout, use it rather than cloning again.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
EXISTING_INSTALL=0
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/menu.sh" ] && [ -d "$SELF_DIR/lib" ]; then
    INSTALL_DIR="$SELF_DIR"
    ok "Using the existing checkout at $INSTALL_DIR"
elif [ -d "$INSTALL_DIR/.git" ]; then
    EXISTING_INSTALL=1
    say "  Found an existing installation at $INSTALL_DIR"
    say "  Updating it"
    if git -C "$INSTALL_DIR" pull --rebase --autostash >/dev/null 2>&1; then
        ok "Updated to the latest version"
    else
        warn "Could not update cleanly — continuing with what is on disk"
        warn "  Resolve with:  git -C '$INSTALL_DIR' status"
    fi
else
    say "  Cloning into $INSTALL_DIR"
    if git clone --depth=1 "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1; then
        ok "Cloned"
    else
        die "Clone failed. Check your connection, or clone manually:
     git clone $REPO_URL $INSTALL_DIR"
    fi
fi

chmod +x "$INSTALL_DIR/menu.sh" "$INSTALL_DIR/install.sh" "$INSTALL_DIR/upgrade.sh" 2>/dev/null || true
find "$INSTALL_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. Terminal UI dependency
# ------------------------------------------------------------------------------
step "3/4  Installing the terminal UI (gum)"

# Optional: every screen has a plain-text fallback, so failure here is not fatal.
if command -v gum >/dev/null 2>&1; then
    ok "gum already installed"
else
    say "  Downloading the Charm repository key"
    if command -v apt-get >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p /etc/apt/keyrings
        if curl -fsSL https://repo.charm.sh/apt/gpg.key 2>/dev/null \
            | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null; then
            printf 'deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *\n' \
                | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
            sudo apt-get update -y >/dev/null 2>&1
            if sudo apt-get install -y gum >/dev/null 2>&1; then
                ok "gum installed"
            else
                warn "gum could not be installed — the toolkit will use the text menu"
            fi
        else
            warn "Could not fetch the Charm repository key — using the text menu"
        fi
    else
        warn "apt-get or sudo unavailable — using the text menu"
    fi
fi

# ------------------------------------------------------------------------------
# 4. Hand over
# ------------------------------------------------------------------------------
step "4/4  Ready"

# An existing installation should be upgraded, not treated as a fresh setup:
# that path also migrates old configuration and rebuilds against the newest ROCm.
if [ "$EXISTING_INSTALL" = "1" ] && [ -f "$INSTALL_DIR/upgrade.sh" ]; then
    say ""
    say "  ${BOLD}This looks like an existing installation.${RESET}"
    say "    Running the automatic upgrade, which will:"
    say "      • update the toolkit"
    say "      • migrate settings that older versions left harmful"
    say "      • upgrade ROCm and rebuild PyTorch against it"
    say "      • reinstall your tools' dependencies and re-tune performance"
    say ""
    say "    Your models, custom nodes and datasets are never touched."
    say ""
    if [ -t 0 ]; then
        printf '  Press Enter to start the upgrade (Ctrl+C to skip)...'
        read -r _
        echo ""
        cd "$INSTALL_DIR" || die "Could not enter $INSTALL_DIR"
        exec ./upgrade.sh
    else
        say "  Run it now:   cd $INSTALL_DIR && ./upgrade.sh"
        say ""
        exit 0
    fi
fi

say ""
say "  ${BOLD}What happens next${RESET}"
say "    The menu opens. Choose ${BOLD}Quick start${RESET} and it will walk you"
say "    through the base environment install, then tuning, then your first tool."
say ""
say "  ${BOLD}Before you install the base environment, Windows needs:${RESET}"
say "    • AMD Adrenalin driver 26.2.2 or newer"
say "      https://www.amd.com/en/support/download/drivers.html"
say "    • The Windows SDK (used to build the ROCDXG GPU bridge)"
say "      https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/"
say ""
say "    Missing either one is the most common reason installation fails."
say "    Settings -> GPU diagnostics checks both for you."
say ""

cd "$INSTALL_DIR" || die "Could not enter $INSTALL_DIR"

if [ -t 0 ] && [ -t 1 ]; then
    printf '  Press Enter to open the menu...'
    read -r _
    exec ./menu.sh
else
    # Piped install (curl | bash): no terminal to hand over to.
    say "  ${BOLD}Done.${RESET} Now run:"
    say "      cd $INSTALL_DIR && ./menu.sh"
    say ""
fi
