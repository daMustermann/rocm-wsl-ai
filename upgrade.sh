#!/bin/bash
# ==============================================================================
# ROCm WSL2 AI Toolkit — Automatic upgrade
# ==============================================================================
# One command that brings an older installation fully up to date:
#
#   ./upgrade.sh              check everything, then upgrade what needs it
#   ./upgrade.sh --check      report only, change nothing
#   ./upgrade.sh --yes        no prompts (for scripts)
#   ./upgrade.sh --rocm-only  skip the toolkit update
#   ./upgrade.sh --force      reinstall even if versions look current
#
# The stages, in order:
#
#   1. Detect      what is installed, and what AMD currently publishes
#   2. Report      one table, so the user sees the plan before anything happens
#   3. Toolkit     git pull to the latest release, then re-exec the new code
#   4. Migrate     repair configuration that older versions left harmful
#   5. Shell       install the GPU environment for login shells
#   6. ROCm        upgrade to the newest release with matching PyTorch wheels
#   7. Environment rebuild ~/genai_env against the new stack
#   8. Tools       reinstall every tool's dependencies against the new stack
#   9. Retune      re-measure performance, because the old profile is stale
#  10. Verify      confirm the GPU works and report
#
# Models, custom nodes, extensions, datasets and settings are never touched.
# The old environment is moved aside rather than deleted.
#
# Version numbers are resolved from AMD's repositories at run time (see
# lib/version.sh), never hardcoded. A future ROCm release therefore becomes
# available without editing this script.
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

mkdir -p "$ROCM_AI_CONFIG_DIR" 2>/dev/null || true
mkdir -p "$ROCM_AI_CONFIG_DIR/logs" 2>/dev/null || true
ensure_user_env >/dev/null 2>&1 || true
load_user_env >/dev/null 2>&1 || true

LOG_FILE="$ROCM_AI_CONFIG_DIR/logs/upgrade-$(date +%Y%m%d-%H%M%S).log"

# lib/common.sh only defines the colour variables when stdout is a terminal, so
# anything that reads them unconditionally breaks the moment output is piped to a
# file or through `tail` (which is exactly how people capture a failed upgrade).
# Define safe fallbacks rather than relying on the caller's terminal.
: "${_C_RESET:=}"
: "${_C_BOLD:=}"
: "${_C_DIM:=}"
: "${_C_OK:=}"
: "${_C_WARN:=}"
: "${_C_ERR:=}"
: "${_C_ACC:=}"
: "${_C_INFO:=}"

# --- Options -----------------------------------------------------------------
OPT_CHECK_ONLY=0
OPT_YES=0
OPT_FORCE=0
OPT_SKIP_TOOLKIT=0
OPT_SKIP_RETUNE=0

# Which ROCm release stream to move to.
#
#   core    ROCm 10.x. Packages become amdrocm10.1-gfx1100 from
#           stable.repo.amd.com under /opt/rocm/core-10.1, PyTorch comes from
#           pip with a device extra, and librocdxg arrives inside ROCm — so the
#           Windows SDK and the from-source ROCDXG build are no longer needed.
#   legacy  ROCm 7.2.x, kept because WSL support in 10.x is a technical preview.
#
# `core` is the default. Switching from legacy to core is destructive and needs
# its own confirmation, because it removes the ROCm packages that are currently
# working on the machine.
TARGET_CHANNEL="${ROCM_AI_CHANNEL:-core}"
export ROCM_AI_CHANNEL="$TARGET_CHANNEL"

while [ $# -gt 0 ]; do
    case "$1" in
        --check|--dry-run) OPT_CHECK_ONLY=1 ;;
        -y|--yes)          OPT_YES=1 ;;
        --force)           OPT_FORCE=1 ;;
        --rocm-only)       OPT_SKIP_TOOLKIT=1 ;;
        --no-retune)       OPT_SKIP_RETUNE=1 ;;
        --target)
            shift
            case "${1:-}" in
                core|legacy)
                    TARGET_CHANNEL="$1"
                    export ROCM_AI_CHANNEL="$1"
                    ;;
                *)
                    warn "--target expects 'core' or 'legacy', not '${1:-}'"
                    exit 2
                    ;;
            esac
            ;;
        -h|--help)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) warn "Unknown option: $1" ;;
    esac
    shift
done

if [ "$OPT_YES" = "1" ]; then
    # Make `confirm` and `yesno` non-interactive.
    confirm() { return 0; }
    yesno()   { return 0; }
fi

# Everything is logged, so a failed upgrade can be diagnosed after the fact.
exec > >(tee -a "$LOG_FILE") 2>&1

confirm_or_skip() {
    local msg="$1"
    [ "$OPT_YES" = "1" ] && return 0
    confirm "$msg"
}

# The ROCm and ROCDXG stages need root. Discovering that *after* downloading
# several gigabytes would waste the user's time and leave the machine half
# upgraded, so it is checked up front.
#
# `sudo -n -v` validates a cached credential without prompting. If that fails,
# `sudo -v` is tried so the password is asked for once and cached for the rest of
# the run. With no terminal to prompt on, that fails too, and the caller is told
# plainly instead of stalling at the least convenient moment.
SUDO_MODE="unknown"
SUDO_KEEPALIVE_PID=""

acquire_sudo() {
    if sudo -n -v 2>/dev/null; then
        SUDO_MODE="cached"
        return 0
    fi

    if [ ! -t 0 ]; then
        SUDO_MODE="unavailable"
        return 1
    fi

    printf '\n'
    printf '  Upgrading ROCm needs administrator rights. Your password is asked\n'
    printf '  for once here and reused for the rest of the upgrade.\n\n'
    if sudo -v; then
        SUDO_MODE="prompted"
        # Keep the credential warm: the default timeout is 15 minutes and the
        # ROCm download can easily exceed that.
        ( while true; do sudo -n -v 2>/dev/null || exit 0; sleep 50; done ) &
        SUDO_KEEPALIVE_PID=$!
        return 0
    fi

    SUDO_MODE="unavailable"
    return 1
}

release_sudo() {
    [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    return 0
}

# ==============================================================================
# Stage 1 — Detect
# ==============================================================================

detect_state() {
    CODENAME="$(va_ubuntu_codename)"
    VENV_PY="$HOME/genai_env/bin/python3"
    PYTAG="$(va_python_tag "$VENV_PY" 2>/dev/null || va_python_tag python3)"

    TOOLKIT_LOCAL="$(va_toolkit_local_version "$TOOLKIT_ROOT")"

    ROCM_NOW="$(va_rocm_installed 2>/dev/null || true)"
    ROCDXG_NOW="$(va_rocdxg_installed 2>/dev/null || true)"
    TORCH_NOW="$(va_torch_installed "$VENV_PY" 2>/dev/null || true)"
    TORCH_HIP_NOW="$(va_torch_hip_version "$VENV_PY" 2>/dev/null || true)"

    INSTALL_KIND="$(va_install_kind)"

    # Which GPU architecture to install for. Every core-channel package name and
    # every pip device extra is keyed on it, so it is resolved once here and
    # reused by the plan, the install and the verification.
    #
    # user.env is consulted first: once a machine has been installed for a
    # specific target, that recorded choice outranks detection, so a later
    # upgrade keeps the same architecture even if a second GPU appears.
    GFX_TARGET=""
    if [ -f "$USER_ENV" ]; then
        GFX_TARGET="$(sed -n 's/^export AMDROCM_DEVICE_TARGET="\(.*\)"$/\1/p' "$USER_ENV" \
            | head -1)"
    fi
    [ -z "$GFX_TARGET" ] && GFX_TARGET="${AMDROCM_DEVICE_TARGET:-}"
    [ -z "$GFX_TARGET" ] && GFX_TARGET="$(va_gfx_detect 2>/dev/null || true)"

    # A legacy install always has a working ROCm to interrogate, so by the time
    # we need this on a real migration it is normally known.
    if [ -z "$GFX_TARGET" ] && [ -x /opt/rocm/bin/rocminfo ]; then
        GFX_TARGET="$(/opt/rocm/bin/rocminfo 2>/dev/null \
            | grep -oE 'Name:[[:space:]]+gfx[0-9a-z]+' | awk '{print $2}' | head -1)"
    fi
    GFX_TARGET="${GFX_TARGET#gfx}"

    # A legacy 7.2.x stack present while targeting core is the migration case.
    # It is a different job from an in-place version bump: the old packages have
    # to be removed, not upgraded.
    NEED_LEGACY_PURGE=0
    if [ "$TARGET_CHANNEL" = "core" ]; then
        case "$INSTALL_KIND" in
            legacy|both) NEED_LEGACY_PURGE=1 ;;
        esac
    fi

    if [ "$TARGET_CHANNEL" = "legacy" ]; then
        log "Targeting the legacy ROCm 7.2.x channel ..."
        ROCM_NEW="$(va_latest_legacy_rocm "$CODENAME")"
        ROCDXG_NEW="$(va_latest_librocdxg)"
        ROCM_WITH_WHEELS="$(va_best_installable_rocm "$PYTAG")"
        TORCH_TARGET="$(
            va_resolve_torch_wheels "$ROCM_WITH_WHEELS" "$PYTAG" 2>/dev/null \
                | sed -n 's/^TORCH_VERSION=//p'
        )"
    else
        log "Querying AMD's repositories for the newest ROCm 10.x release ..."
        ROCM_NEW="$(va_latest_core_series)"
        # librocdxg ships inside ROCm on this channel, so there is no separate
        # library version to compare against and nothing to build.
        ROCDXG_NEW=""
        ROCM_TARGET_NOTE=""

        # Resolve the full install plan once, up front. Everything downstream
        # reads these values rather than re-querying, so the plan that gets
        # reported is exactly the plan that gets executed.
        if UPGRADE_SPEC="$(va_resolve_torch_spec "$GFX_TARGET" "$PYTAG")"; then
            eval "$UPGRADE_SPEC"
            ROCM_WITH_WHEELS="$ROCM_SERIES"
            ROCM_TARGET="$ROCM_SERIES"
            TORCH_TARGET="$TORCH_VERSION"
        else
            warn "Could not resolve a ROCm 10.x release with wheels for ${PYTAG}."
            warn "Falling back to reporting the newest series without a plan."
            ROCM_WITH_WHEELS="$ROCM_NEW"
            ROCM_TARGET="$ROCM_NEW"
            TORCH_TARGET=""
        fi
    fi

    # The ROCm release we will actually install has to have wheels for this
    # Python, or the environment rebuild would fail after ROCm was already
    # replaced.
    if [ "$TARGET_CHANNEL" = "legacy" ] \
       && [ -n "${ROCM_WITH_WHEELS:-}" ] && va_lt "$ROCM_WITH_WHEELS" "$ROCM_NEW"; then
        ROCM_TARGET="$ROCM_WITH_WHEELS"
        ROCM_TARGET_NOTE=" (newest with PyTorch wheels for Python ${PYTAG#cp})"
    fi

    TOOLKIT_REMOTE=""
    if [ -d "$TOOLKIT_ROOT/.git" ]; then
        TOOLKIT_BRANCH="$(git -C "$TOOLKIT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
        if git -C "$TOOLKIT_ROOT" fetch origin --quiet 2>/dev/null; then
            TOOLKIT_REMOTE="$(va_toolkit_remote_version "$TOOLKIT_ROOT" "$TOOLKIT_BRANCH")"
        fi
    fi
}

# Decide what actually needs doing.
plan_work() {
    NEED_TOOLKIT=0
    NEED_ROCM=0
    NEED_ROCDXG=0
    NEED_ENV=0
    NEED_MIGRATE=0
    NEED_SHELL=0
    NEED_TOOLS=0

    # Toolkit
    if [ "$OPT_SKIP_TOOLKIT" = "1" ]; then
        :
    elif [ -n "${TOOLKIT_REMOTE:-}" ]; then
        if [ "$OPT_FORCE" = "1" ] || va_lt "$TOOLKIT_LOCAL" "$TOOLKIT_REMOTE"; then
            NEED_TOOLKIT=1
        fi
    fi

    # ROCm. Removing a legacy stack counts as needing ROCm work: the core
    # packages still have to be installed afterwards.
    if [ "$OPT_FORCE" = "1" ] || [ "${NEED_LEGACY_PURGE:-0}" = "1" ]; then
        NEED_ROCM=1
    elif [ -z "${ROCM_NOW:-}" ]; then
        NEED_ROCM=1
    elif va_lt "$ROCM_NOW" "$ROCM_TARGET"; then
        NEED_ROCM=1
    fi

    # The WSL GPU bridge. Only the legacy channel has something to do here:
    # ROCm 10.x ships librocdxg and the runtime loads it automatically.
    if [ "$TARGET_CHANNEL" = "legacy" ]; then
        if [ -z "${ROCDXG_NOW:-}" ]; then
            NEED_ROCDXG=1
        elif [ -n "${ROCDXG_NEW:-}" ] && [ "$OPT_FORCE" = "1" ]; then
            NEED_ROCDXG=1
        elif [ -n "${ROCDXG_NEW:-}" ]; then
            local want="${ROCDXG_NEW#v}"
            va_lt "$ROCDXG_NOW" "$want" && NEED_ROCDXG=1
        fi
    fi

    # Python environment: rebuild when ROCm or PyTorch moved, or torch is absent
    # or is not a HIP build.
    if [ "$OPT_FORCE" = "1" ] || [ "$NEED_ROCM" = "1" ] || [ ! -x "$VENV_PY" ]; then
        NEED_ENV=1
    elif [ -n "${TORCH_NOW:-}" ] && [ -z "${TORCH_HIP_NOW:-}" ]; then
        NEED_ENV=1
    elif [ -n "${TORCH_NOW:-}" ] && [ -n "${ROCM_NOW:-}" ]; then
        # torch built against an older ROCm than installed
        case "$TORCH_NOW" in
            *"rocm${ROCM_NOW}"*) : ;;
            *"rocm"*) NEED_ENV=1 ;;
        esac
    fi

    rocm_ai_migration_needed && NEED_MIGRATE=1
    rocm_ai_shell_integration_present || NEED_SHELL=1

    # Tools need their dependencies reinstalled after an environment rebuild.
    [ "$NEED_ENV" = "1" ] && NEED_TOOLS=1

    # Root is required for the ROCm stage, the ROCDXG build and the login-shell
    # drop-in. Decide now whether that is actually obtainable.
    NEED_SUDO=0
    if [ "$NEED_ROCM" = "1" ] || [ "$NEED_ROCDXG" = "1" ] || [ "$NEED_SHELL" = "1" ] \
       || [ "${NEED_LEGACY_PURGE:-0}" = "1" ]; then
        NEED_SUDO=1
    fi
}

# ==============================================================================
# Stage 2 — Report
# ==============================================================================

report_plan() {
    clear
    printf '\n'
    if _rocm_ai_have_gum; then
        gum style --border double --margin "0 2" --padding "0 2" --border-foreground 212 --align center \
            "$(gum style --bold --foreground 212 "ROCm WSL2 AI Toolkit — upgrade")" \
            "$(gum style --foreground 240 "checking what needs updating")"
    else
        printf '=== ROCm WSL2 AI Toolkit — upgrade ===\n'
    fi
    printf '\n'

    printf '   %-22s %-26s %s\n' "COMPONENT" "INSTALLED" "AVAILABLE"
    printf '   %s\n' "$(printf '─%.0s' $(seq 1 68))"

    local t_mark="" r_mark="" x_mark="" e_mark="" m_mark="" s_mark="" p_mark=""

    # Target channel, stated up front because it decides everything else.
    printf '\n'
    if [ "$TARGET_CHANNEL" = "legacy" ]; then
        printf '   %bTarget%b legacy ROCm 7.2.x channel (--target legacy)\n' \
            "$_C_INFO" "$_C_RESET"
    else
        printf '   %bTarget%b ROCm %s core channel · architecture gfx%s\n' \
            "$_C_INFO" "$_C_RESET" "${ROCM_NEW:-?}" "${GFX_TARGET:-?}"
    fi
    printf '\n'

    # Toolkit
    if [ -z "${TOOLKIT_REMOTE:-}" ]; then
        printf '   %-22s %-26s %s\n' "Toolkit" "$TOOLKIT_LOCAL" "unknown (offline?)"
    elif [ "$NEED_TOOLKIT" = "1" ]; then
        printf '   %-22s %-26s %s\n' "Toolkit" "$TOOLKIT_LOCAL" "$TOOLKIT_REMOTE   <- update"
        t_mark="toolkit"
    else
        printf '   %-22s %-26s %s\n' "Toolkit" "$TOOLKIT_LOCAL" "up to date"
    fi

    # ROCm
    # The legacy teardown is listed before ROCm so the destructive step is never
    # hidden below an ordinary-looking upgrade line.
    if [ "${NEED_LEGACY_PURGE:-0}" = "1" ]; then
        printf '   %-22s %-26s %s\n' "Legacy ROCm 7.2.x" \
            "$(va_install_kind)" "will be REMOVED   <- destructive"
        p_mark="purge"
    fi

    if [ "$NEED_ROCM" = "1" ]; then
        if [ "$TARGET_CHANNEL" = "legacy" ]; then
            printf '   %-22s %-26s %s\n' "ROCm" "${ROCM_NOW:-not installed}" "$ROCM_TARGET   <- upgrade"
        else
            printf '   %-22s %-26s %s\n' "ROCm" "${ROCM_NOW:-not installed}" \
                "$(va_core_meta_package "${ROCM_TARGET:-}" "${GFX_TARGET:-}")   <- install"
        fi
        r_mark="rocm"
    else
        printf '   %-22s %-26s %s\n' "ROCm" "${ROCM_NOW:-none}" "up to date"
    fi

    # The WSL GPU bridge. Only actionable on the legacy channel — ROCm 10.x ships
    # librocdxg, so there is nothing to build and nothing to compare against.
    if [ "$TARGET_CHANNEL" = "legacy" ]; then
        if [ "$NEED_ROCDXG" = "1" ]; then
            printf '   %-22s %-26s %s\n' "ROCDXG (WSL bridge)" "${ROCDXG_NOW:-not installed}" "$ROCDXG_NEW   <- rebuild"
            x_mark="rocdxg"
        else
            printf '   %-22s %-26s %s\n' "ROCDXG (WSL bridge)" "${ROCDXG_NOW:-none}" "up to date"
        fi
    elif [ "${NEED_LEGACY_PURGE:-0}" = "1" ] || [ "$NEED_ROCM" = "1" ]; then
        printf '   %-22s %-26s %s\n' "ROCDXG (WSL bridge)" "${ROCDXG_NOW:-none}" "ships with ROCm"
    fi

    # PyTorch
    if [ "$NEED_ENV" = "1" ]; then
        if [ -n "${TORCH_TARGET:-}" ] && [ "$TARGET_CHANNEL" != "legacy" ]; then
            printf '   %-22s %-26s %s\n' "PyTorch" "${TORCH_NOW:-not installed}" \
                "rebuild -> ${TORCH_TARGET}"
        else
            printf '   %-22s %-26s %s\n' "PyTorch" "${TORCH_NOW:-not installed}" \
                "rebuild for ROCm $ROCM_TARGET"
        fi
        e_mark="env"
    else
        printf '   %-22s %-26s %s\n' "PyTorch" "${TORCH_NOW:-none}" "up to date"
    fi

    # Config
    if [ "$NEED_MIGRATE" = "1" ]; then
        printf '   %-22s %-26s %s\n' "Configuration" "3.x-era settings" "needs migrating"
        m_mark="migrate"
    else
        printf '   %-22s %-26s %s\n' "Configuration" "current" "up to date"
    fi

    # Shell integration
    if [ "$NEED_SHELL" = "1" ]; then
        printf '   %-22s %-26s %s\n' "Login-shell GPU env" "not installed" "will install"
        s_mark="shell"
    else
        printf '   %-22s %-26s %s\n' "Login-shell GPU env" "installed" "up to date"
    fi

    printf '   %s\n' "$(printf '─%.0s' $(seq 1 68))"

    if [ "${NEED_SUDO:-0}" = "1" ] && ! sudo -n -v 2>/dev/null; then
        printf '\n'
        printf '   %bNote%b Administrator rights will be requested before any download.\n' \
            "$_C_WARN" "$_C_RESET"
    fi

    if [ -n "$ROCM_TARGET_NOTE" ]; then
        printf '\n   %bNote%b ROCm %s is published but has no PyTorch wheels for\n' \
            "$_C_WARN" "$_C_RESET" "$ROCM_NEW"
        printf '        Python %s, so %s will be installed instead.\n' "${PYTAG#cp}" "$ROCM_TARGET"
    fi

    if [ "${NEED_LEGACY_PURGE:-0}" = "1" ]; then
        printf '\n'
        printf '   %bDESTRUCTIVE%b This upgrade removes your working ROCm 7.2.x packages.\n' \
            "$_C_ERR" "$_C_RESET"
        printf '               AMD requires it: both stacks register /opt/rocm and\n'
        printf '               cannot coexist. Your /opt/rocm-7.2.x directories are\n'
        printf '               set aside, not deleted, so a rollback stays possible.\n'
        printf '               You will be asked to type REMOVE before anything goes.\n'
    fi

    local actions=0
    for m in "$t_mark" "$p_mark" "$r_mark" "$x_mark" "$e_mark" "$m_mark" "$s_mark"; do
        [ -n "$m" ] && actions=$((actions + 1))
    done

    printf '\n'
    if [ "$actions" -eq 0 ]; then
        success "Everything is already up to date."
        printf '\n'
        printf '   Installed : ROCm %s · librocdxg %s · PyTorch %s\n' \
            "${ROCM_NOW:-?}" "${ROCDXG_NOW:-?}" "${TORCH_NOW:-?}"
        printf '   Toolkit   : v%s\n' "$TOOLKIT_LOCAL"
        printf '\n'
        [ "$OPT_FORCE" = "1" ] || return 1
        printf '   --force was given, so the upgrade will run anyway.\n\n'
    else
        printf '   %d component(s) will be updated.\n' "$actions"
    fi
    printf '\n'
    printf '   Your models, custom nodes, extensions and datasets are never touched.\n'
    printf '\n'
    return 0
}

# ==============================================================================
# Stage 3 — Toolkit
# ==============================================================================

upgrade_toolkit() {
    headline "Updating the toolkit"

    if [ ! -d "$TOOLKIT_ROOT/.git" ]; then
        warn "This is not a git checkout, so it cannot update itself."
        warn "Re-run the installer to get the latest version:"
        warn "  curl -fsSL https://raw.githubusercontent.com/daMustermann/rocm-wsl-ai/main/install.sh | bash"
        return 0
    fi

    local dirty
    dirty="$(git -C "$TOOLKIT_ROOT" status --porcelain 2>/dev/null | wc -l)"
    if [ "$dirty" -gt 0 ]; then
        log "$dirty local change(s) found — they will be stashed by --autostash"
    fi

    if git -C "$TOOLKIT_ROOT" pull --rebase --autostash; then
        success "Toolkit updated to v$(va_toolkit_local_version "$TOOLKIT_ROOT")"
        return 0
    fi

    err "The toolkit update did not complete."
    err "Resolve it by hand, then re-run this script:"
    err "  git -C '$TOOLKIT_ROOT' status"
    err "  git -C '$TOOLKIT_ROOT' pull --rebase --autostash"
    return 1
}

# After the toolkit updates itself, this running process still holds the OLD
# code in memory. Re-executing picks up the new libraries, which matters because
# later stages call into them.
reexec_if_updated() {
    local now
    now="$(va_toolkit_local_version "$TOOLKIT_ROOT")"
    [ "$now" = "${TOOLKIT_LOCAL:-}" ] && return 1
    [ "${ROCM_AI_REEXEC:-0}" = "1" ] && return 1

    log "Restarting the upgrade with the new v$now code ..."
    export ROCM_AI_REEXEC=1
    local -a args=()
    [ "$OPT_YES" = "1" ] && args+=(--yes)
    [ "$OPT_FORCE" = "1" ] && args+=(--force)
    [ "$OPT_SKIP_TOOLKIT" = "1" ] && args+=(--rocm-only)
    [ "$OPT_SKIP_RETUNE" = "1" ] && args+=(--no-retune)
    exec bash "$TOOLKIT_ROOT/upgrade.sh" "${args[@]}"
}

# ==============================================================================
# Stage 4 — Configuration migration
# ==============================================================================

run_migration() {
    headline "Migrating your configuration"
    printf '  Settings from earlier versions are checked and corrected.\n'
    printf '  Every file that changes is backed up first.\n'
    rocm_ai_migrate_config
}

# ==============================================================================
# Stage 5 — Login-shell integration
# ==============================================================================

install_shell_env() {
    headline "Installing the GPU environment for your shell"
    printf '  This lets PyTorch find the GPU from any terminal, not only inside\n'
    printf '  an activated virtual environment.\n\n'

    if rocm_ai_install_shell_integration; then
        if [ -f /etc/profile.d/rocm-wsl-ai.sh ]; then
            success "Installed /etc/profile.d/rocm-wsl-ai.sh"
            printf '       Applies to new login shells. Reopen your terminal to pick it up.\n'
        else
            success "Added the GPU environment to ~/.bashrc"
        fi
        # Also keep a toolkit-local copy, which the launchers source.
        rocm_ai_write_env_file >/dev/null 2>&1 || true
    else
        warn "Could not install the shell integration automatically."
        printf '       Run this once by hand if you want it:\n\n'
        printf '         %s\n\n' "$(rocm_ai_write_env_file 2>/dev/null || echo '<could not write>')"
        printf '       Then add to ~/.bashrc:  source <that file>\n'
    fi
}

# ==============================================================================
# Stage 6 — ROCm
# ==============================================================================

# Remove a legacy ROCm 7.2.x stack.
#
# This is the only destructive stage in the upgrade, and it exists because AMD
# requires it: the legacy packages install into /opt/rocm-<version> and register
# /opt/rocm through update-alternatives, while the 10.x packages install into
# /opt/rocm/core-<series> and register the same paths. Leaving both in place
# produces a machine where /opt/rocm points into a tree whose libraries and the
# venv's torch disagree about what ROCm version is present.
#
# AMD's documentation states the requirement but gives no commands, so the exact
# package set is assembled here. The list is deliberately narrow: it names the
# legacy ROCm package families and nothing else, so an unrelated `nvidia-*` or
# system package is never a candidate.
#
# /opt/rocm-<version> directories are MOVED, not deleted. They are large, but a
# rename costs nothing and keeps a way back to a working stack if 10.1's WSL
# preview turns out not to suit this machine.
remove_legacy_rocm() {
    headline "Removing the legacy ROCm 7.2.x stack"

    local dirs
    dirs="$(ls -d /opt/rocm-[0-9]* 2>/dev/null)"
    local count
    count="$(printf '%s\n' "$dirs" | grep -c . || true)"

    printf '  AMD requires ROCm 7.2.x or older to be removed before ROCm 10.x\n'
    printf '  can be installed. Both claim /opt/rocm.\n\n'
    printf '  Will remove these packages:\n'
    printf '    rocm*  hip*  rocblas  rocfft  rocsparse  rocsolver rocrand\n'
    printf '    rocrand  miopen  rccl  rocship  roct  hsa-rocr  comgr\n'
    printf '    amd-smi-lib  rocm-smi-lib  rocm-llvm\n\n'
    if [ "$count" -gt 0 ]; then
        printf '  And set aside these directories (a rename, reversible):\n'
        printf '%s\n' "$dirs" | sed 's/^/    /'
    fi
    printf '\n'

    if [ "$OPT_CHECK_ONLY" != "1" ]; then
        if [ "$OPT_YES" != "1" ]; then
            # Typed confirmation. This stage deletes a working GPU stack, and a
            # stray Enter keypress should not be enough to authorise it.
            printf '  Type REMOVE to proceed: ' >&2
            local typed=""
            read -r typed || typed=""
            printf '\n'
            if [ "$typed" != "REMOVE" ]; then
                err "Not confirmed. Nothing was removed."
                err "The legacy stack is still installed, so ROCm 10.x cannot proceed."
                exit 1
            fi
        fi

        log "Removing legacy ROCm packages ..."
        sudo apt-get purge -y \
            'rocm*' 'hip*' 'rocblas' 'rocfft' 'rocsparse' 'rocsolver' 'rocrand' \
            'miopen' 'rccl' 'rocship' 'roct' 'hsa-rocr' 'comgr' \
            'amd-smi-lib' 'rocm-smi-lib' 'rocm-llvm' \
            >/dev/null 2>&1 || warn "Some legacy packages were not present; continuing."

        # The legacy apt sources point at repo.radeon.com/rocm/apt, which would
        # otherwise keep offering the old packages on every future `apt update`.
        local src
        for src in /etc/apt/sources.list.d/rocm.list \
                   /etc/apt/sources.list.d/rocm-graphics.list; do
            if [ -f "$src" ]; then
                log "Removing legacy apt source $src"
                sudo rm -f "$src" || true
            fi
        done

        # `apt autoremove` reclaims the dependencies ROCm pulled in.
        sudo apt-get autoremove -y >/dev/null 2>&1 || true

        # /opt/rocm is an update-alternatives symlink owned by the removed
        # packages. Purge usually leaves it dangling, which breaks tools that
        # test -e /opt/rocm.
        if [ -L /opt/rocm ] && [ ! -e /opt/rocm ]; then
            log "Removing dangling /opt/rocm symlink (recreated by ROCm 10.x)"
            sudo rm -f /opt/rocm || true
        fi

        local stamp d
        stamp="$(date +%Y%m%d%H%M%S)"
        for d in $dirs; do
            [ -d "$d" ] || continue
            log "Setting aside $d -> ${d}.retired-${stamp}"
            sudo mv "$d" "${d}.retired-${stamp}" || warn "Could not move $d"
        done
        sudo ldconfig || true

        success "Legacy ROCm stack removed."
        if [ "$count" -gt 0 ]; then
            printf '\n'
            log "To roll back later, move the directory back and reinstall the"
            log "legacy packages. Nothing was deleted."
        fi
    fi
}

upgrade_rocm() {
    if [ "$TARGET_CHANNEL" = "legacy" ]; then
        upgrade_rocm_legacy
        return $?
    fi

    headline "Installing ROCm ${ROCM_TARGET} (series) for gfx${GFX_TARGET:-unknown}"

    printf '  From: %s\n' "${ROCM_NOW:-nothing}"
    printf '  To  : ROCm %s, architecture package for %s\n\n' \
        "${ROCM_VERSION:-?}" "${GFX_TARGET:-unknown}"

    if [ -z "${GFX_TARGET:-}" ]; then
        err "Could not determine your GPU architecture."
        err "Set it in $USER_ENV as AMDROCM_DEVICE_TARGET=\"gfx1100\", or run"
        err "./scripts/install/setup_pytorch_rocm.sh which will ask."
        return 1
    fi

    local keyring="/etc/apt/keyrings/amdrocm.gpg"
    if [ ! -f "$keyring" ]; then
        log "Installing AMD's signing key"
        sudo mkdir -p /etc/apt/keyrings
        if ! curl -fsSL "$ROCM_AI_AMD_GPG_KEY" | gpg --dearmor | sudo tee "$keyring" >/dev/null; then
            err "Could not install the ROCm signing key from ${ROCM_AI_AMD_GPG_KEY}"
            return 1
        fi
        success "Signing key installed"
    fi

    # Overwrite rather than append. A leftover stanza pointing at a different
    # series is the usual cause of "no candidate version for amdrocm10.1-gfx1100".
    log "Writing the ROCm apt source"
    if ! va_core_apt_source | sudo tee /etc/apt/sources.list.d/amdrocm-stable.sources >/dev/null; then
        err "Could not write /etc/apt/sources.list.d/amdrocm-stable.sources"
        return 1
    fi

    log "Refreshing package lists"
    sudo apt-get update -y >/dev/null 2>&1 || {
        err "apt-get update failed; the ROCm repository may be unreachable."
        return 1
    }

    # Only the architecture package for this GPU, not every supported one.
    local pkg
    pkg="$(va_core_meta_package "$ROCM_TARGET" "$GFX_TARGET")"
    log "Installing ${pkg} (several GB)"
    if ! sudo apt-get install -y "$pkg"; then
        err "ROCm installation failed."
        err "Confirm ${pkg} exists for this Ubuntu release at:"
        err "    $(va_core_apt_base 2>/dev/null)/"
        return 1
    fi

    success "ROCm installed. Version reported: $(va_rocm_installed 2>/dev/null || echo unknown)"

    # ROCm 10.x ships librocdxg, so the only thing to confirm is that the WSL
    # bridge device exists. If it does not, nothing downstream can work.
    if [ ! -c /dev/dxg ]; then
        warn "/dev/dxg is missing — WSL2 cannot reach the GPU."
        warn "Run 'wsl --shutdown' from PowerShell, then reopen WSL."
    fi
    if has_rocdxg; then
        success "librocdxg present (ships with ROCm; no build step needed)"
    else
        warn "librocdxg not found in the ROCm tree."
        warn "If the GPU stays invisible:  find /opt/rocm -name 'librocdxg*'"
    fi
}

# Legacy 7.2.x channel: repository from repo.radeon.com, package `rocm`, and
# librocdxg built from source. Kept intact so `--target legacy` remains a real
# fallback rather than a note in the documentation.
upgrade_rocm_legacy() {
    headline "Upgrading ROCm to ${ROCM_TARGET} (legacy channel)"

    local codename="$CODENAME"
    local keyring="/etc/apt/keyrings/rocm.gpg"

    printf '  From: %s\n' "${ROCM_NOW:-nothing}"
    printf '  To  : %s\n\n' "$ROCM_TARGET"

    # --- Repository key -------------------------------------------------------
    if [ ! -f "$keyring" ]; then
        log "Installing AMD's signing key"
        if command -v wget >/dev/null 2>&1; then
            sudo mkdir -p /etc/apt/keyrings
            wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key \
                | gpg --dearmor | sudo tee "$keyring" >/dev/null || {
                    err "Could not install the ROCm signing key."
                    err "Check your internet connection."
                    return 1
                }
        fi
    fi

    # --- Point apt at the target release -------------------------------------
    # Amends any previous rocm/apt source instead of only adding a new one, so
    # apt cannot end up with two competing ROCm repositories.
    #
    # The host is interpolated from $ROCM_AI_REPO rather than written out, so the
    # legacy URL exists in exactly one place (lib/version.sh) and the CI guard
    # that forbids hardcoded upstream hosts stays meaningful.
    log "Configuring the apt source for ROCm ${ROCM_TARGET}"
    local legacy_base="$ROCM_AI_REPO/rocm/apt"
    local sources
    sources="$(grep -rl "$legacy_base" /etc/apt/sources.list.d/ 2>/dev/null | head -1)"

    if [ -n "$sources" ]; then
        sudo sed -i -E "s|${legacy_base//./\\.}/[0-9.]+|${legacy_base}/${ROCM_TARGET}|g" "$sources" \
            || warn "Could not rewrite $sources — continuing"
        log "Updated existing source: $sources"
    else
        printf 'deb [arch=amd64 signed-by=%s] %s/rocm/apt/%s %s main\n' \
            "$keyring" "$ROCM_AI_REPO" "$ROCM_TARGET" "$codename" \
            | sudo tee /etc/apt/sources.list.d/rocm.list >/dev/null || {
                err "Could not write the ROCm apt source."
                return 1
            }
        log "Created /etc/apt/sources.list.d/rocm.list"
    fi

    # The graphics repo carries userspace components ROCm depends on.
    if _va_curl -o /dev/null "$ROCM_AI_REPO/graphics/${ROCM_TARGET}/ubuntu/dists/${codename}/Release"; then
        local gsource
        gsource="$(grep -rl 'repo.radeon.com/graphics' /etc/apt/sources.list.d/ 2>/dev/null | head -1)"
        if [ -n "$gsource" ]; then
            sudo sed -i -E "s|repo\.radeon\.com/graphics/[0-9.]+|repo.radeon.com/graphics/${ROCM_TARGET}|g" "$gsource" || true
        else
            printf 'deb [arch=amd64 signed-by=%s] %s/graphics/%s/ubuntu %s main\n' \
                "$keyring" "$ROCM_AI_REPO" "$ROCM_TARGET" "$codename" \
                | sudo tee /etc/apt/sources.list.d/rocm-graphics.list >/dev/null || true
        fi
    fi

    log "Refreshing package lists"
    sudo apt-get update -y >/dev/null 2>&1 || {
        err "apt update failed. The ROCm ${ROCM_TARGET} repository may not be reachable."
        return 1
    }

    # --- Install --------------------------------------------------------------
    log "Installing ROCm ${ROCM_TARGET} (this downloads several GB; it can take a while)"
    if ! sudo apt-get install -y rocm; then
        err "ROCm installation failed."
        err "The previous installation is still intact."
        err "Diagnose with:  sudo apt-get install -y rocm"
        return 1
    fi

    # Keep group membership current; the WSL restart applies it.
    sudo usermod -a -G render,video "$LOGNAME" 2>/dev/null || true

    local installed
    installed="$(va_rocm_installed 2>/dev/null || echo unknown)"
    success "ROCm is now ${installed}"
    return 0
}

# ==============================================================================
# Stage 6b — ROCDXG (the WSL GPU bridge)
# ==============================================================================

upgrade_rocdxg() {
    headline "Rebuilding ROCDXG (the WSL GPU bridge)"

    printf '  From: %s\n' "${ROCDXG_NOW:-nothing}"
    printf '  To  : %s\n\n' "$ROCDXG_NEW"

    # Windows SDK headers are required to build the bridge.
    local win_kits="/mnt/c/Program Files (x86)/Windows Kits/10/Include"
    local win_sdk=""
    if [ -d "$win_kits" ]; then
        local ver
        ver="$(ls -1 "$win_kits" 2>/dev/null | grep -E '^10\.' | sort -V | tail -1)"
        [ -n "$ver" ] && win_sdk="$win_kits/$ver"
    fi

    if [ -z "$win_sdk" ]; then
        err "The Windows SDK was not found, so ROCDXG cannot be built."
        err ""
        err "Install it on Windows, then re-run this upgrade:"
        err "  https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/"
        err ""
        err "During setup, tick 'Windows SDK for Desktop C++ amd64 Apps'."
        warn "Skipping the ROCDXG step; your existing bridge is untouched."
        return 1
    fi
    success "Windows SDK found: $win_sdk"

    ensure_apt_packages build-essential cmake gcc pkg-config libnuma-dev >/dev/null 2>&1 || true

    local build_dir="/tmp/librocdxg-build.$$"
    rm -rf "$build_dir"

    # Prefer the newest release tag; fall back to the default branch.
    local tag="$ROCDXG_NEW"
    log "Cloning ROCm/librocdxg ${tag}"
    if ! git clone --depth=1 --branch "$tag" https://github.com/ROCm/librocdxg.git "$build_dir" 2>/dev/null; then
        warn "Tag ${tag} could not be cloned; using the default branch instead."
        if ! git clone --depth=1 https://github.com/ROCm/librocdxg.git "$build_dir" 2>/dev/null; then
            err "Could not clone ROCm/librocdxg. Check your connection."
            rm -rf "$build_dir"
            return 1
        fi
    fi

    local ok=0
    if (
        set -e
        mkdir -p "$build_dir/build"
        cd "$build_dir/build"
        cmake .. -DWIN_SDK="${win_sdk}/shared" >/dev/null
        make -j"$(nproc 2>/dev/null || echo 4)"
    ); then
        if (cd "$build_dir/build" && sudo make install >/dev/null 2>&1); then
            ok=1
        fi
    fi

    rm -rf "$build_dir"

    if [ "$ok" != "1" ]; then
        err "The ROCDXG build failed."
        err "Your previous bridge is still in place, so nothing is broken."
        err "See docs/TROUBLESHOOTING.md -> 'Windows SDK not found'."
        return 1
    fi

    sudo ldconfig 2>/dev/null || true

    local now
    now="$(va_rocdxg_installed 2>/dev/null || echo unknown)"
    success "ROCDXG rebuilt (version ${now})"

    # A stale bridge can leave the GPU invisible; make sure the env is right.
    export HSA_ENABLE_DXG_DETECTION=1
    unset HSA_OVERRIDE_GFX_VERSION
    return 0
}

# ==============================================================================
# Stage 7 — Python environment
# ==============================================================================

rebuild_environment() {
    if [ "$TARGET_CHANNEL" = "legacy" ]; then
        rebuild_environment_legacy
        return $?
    fi

    headline "Rebuilding the Python environment for ROCm ${ROCM_SERIES}"

    local venv="$HOME/genai_env"
    local backup=""

    if [ -d "$venv" ]; then
        backup="${venv}_backup_$(date +%Y%m%d_%H%M%S)"
        log "Moving the current environment to ${backup/#$HOME/\~}"
        mv "$venv" "$backup" || { err "Could not move $venv aside."; return 1; }
    fi

    # Match the interpreter to the release, the same way the installer does.
    local pybin="python$(case "$CODENAME" in
        jammy) printf '3.10' ;; noble) printf '3.12' ;; resolute) printf '3.13' ;;
        *) printf '' ;; esac)"
    [ -n "$pybin" ] && command -v "$pybin" >/dev/null 2>&1 || pybin="python3"

    log "Creating a fresh environment with ${pybin}"
    if ! "$pybin" -m venv "$venv"; then
        err "Could not create the virtual environment."
        [ -n "$backup" ] && err "Your previous environment is at $backup"
        return 1
    fi

    # shellcheck disable=SC1091
    . "$venv/bin/activate"
    export PIP_USER=0
    pip install --quiet --upgrade pip wheel >/dev/null 2>&1 || warn "pip upgrade had issues"

    # Re-resolve rather than trusting the plan: between `--check` and this point
    # the index may have moved, and installing a version that does not exist
    # would fail deep inside pip instead of here where it can be explained.
    local spec
    if ! spec="$(va_resolve_torch_spec "$GFX_TARGET" "$PYTAG")"; then
        err "Could not resolve PyTorch for ROCm ${ROCM_SERIES} and Python ${PYTAG}."
        err "Index: ${ROCM_AI_WHL_INDEX}"
        if [ -n "$backup" ]; then
            warn "Restoring your previous environment."
            rm -rf "$venv"
            mv "$backup" "$venv"
        fi
        return 1
    fi
    eval "$spec"

    printf '       PyTorch %s · torchvision · torchaudio · ROCm %s\n' \
        "$TORCH_VERSION" "$ROCM_VERSION"
    printf '       device extra: %s\n\n' "$DEVICE_TARGET"

    # A leftover CUDA torch is the most common cause of "the GPU is invisible".
    pip uninstall -y torch torchvision torchaudio triton triton-kernels 2>/dev/null || true

    log "Installing from ${PIP_INDEX} (this takes a few minutes)"
    if ! pip install --index-url "$PIP_INDEX" \
            "$PIP_SPEC_ROCM" "$PIP_SPEC_TORCH" \
            "$PIP_SPEC_TORCHVISION" "$PIP_SPEC_TORCHAUDIO"; then
        err "PyTorch installation failed."
        err "If this is a device-extra problem, 'torch[device-all]' usually works:"
        err "    pip install --index-url ${PIP_INDEX} 'rocm[libraries,device-all]' 'torch[device-all]'"
        [ -n "$backup" ] && err "Previous environment preserved at $backup"
        return 1
    fi

    pip install --no-cache-dir sageattention >/dev/null 2>&1 \
        && log "SageAttention installed" \
        || warn "SageAttention not installed (optional — see docs/PERFORMANCE.md)"

    # --- Bundled HSA runtime --------------------------------------------------
    # A 7.2.x-era torch bundled an HSA runtime that conflicted with ROCm's and
    # could crash the process on import. Whether it still applies is measured:
    # only remove the bundled copy if the GPU is invisible AND it exists.
    local loc torch_lib
    loc="$(pip show torch 2>/dev/null | awk -F ': ' '/^Location/{print $2}')"
    torch_lib="$loc/torch/lib"
    if [ -n "$loc" ] && [ -d "$torch_lib" ]; then
        if python -c 'import torch,sys; sys.exit(0 if torch.cuda.is_available() else 1)' 2>/dev/null; then
            log "GPU already visible; torch's bundled libraries left untouched"
        elif ls "$torch_lib"/libhsa-runtime64.so* >/dev/null 2>&1; then
            rm -f "$torch_lib"/libhsa-runtime64.so* 2>/dev/null
            log "Removed torch's bundled HSA runtime so ROCm's is used"
        fi
    fi

    # Record the architecture so a future rebuild reinstalls the same target.
    _update_user_env "AMDROCM_DEVICE_TARGET" "gfx${GFX_TARGET}"

    # --- venv activation ------------------------------------------------------
    # Deliberately minimal: the launcher supplies the real environment, and
    # PYTORCH_HIP_ALLOC_CONF must never appear here again.
    {
        printf '\nexport HSA_ENABLE_DXG_DETECTION=1\n'
        printf 'export PIP_USER=0\n'
    } >> "$venv/bin/activate"

    deactivate 2>/dev/null || true

    success "Environment rebuilt with PyTorch ${TORCH_VERSION} (ROCm ${ROCM_VERSION})"

    if [ -n "$backup" ]; then
        printf '\n       The previous environment is preserved at:\n'
        printf '         %s\n' "$backup"
        printf '       Delete it once you have confirmed everything works:\n'
        printf '         rm -rf %s\n' "$backup"
    fi

    return 0
}

# Legacy channel: wheels are downloaded by filename from repo.radeon.com.
rebuild_environment_legacy() {
    headline "Rebuilding the Python environment for ROCm ${ROCM_TARGET}"

    local venv="$HOME/genai_env"
    local backup=""

    # Move the old environment aside rather than deleting it, so a failed
    # rebuild is recoverable by hand.
    if [ -d "$venv" ]; then
        backup="${venv}_backup_$(date +%Y%m%d_%H%M%S)"
        log "Moving the current environment to ${backup/#$HOME/\~}"
        mv "$venv" "$backup" || { err "Could not move $venv aside."; return 1; }
    fi

    log "Creating a fresh environment"
    if ! python3 -m venv "$venv"; then
        err "Could not create the virtual environment."
        [ -n "$backup" ] && err "Your previous environment is at $backup"
        return 1
    fi

    # shellcheck disable=SC1091
    . "$venv/bin/activate"
    export PIP_USER=0

    pip install --upgrade pip wheel >/dev/null 2>&1 || warn "pip upgrade had issues"

    # Resolve exact wheels for this ROCm release and Python version.
    log "Resolving PyTorch wheels for ROCm ${ROCM_TARGET} / ${PYTAG}"
    local wheels
    if ! wheels="$(va_resolve_torch_wheels "$ROCM_TARGET" "$PYTAG")"; then
        err "Could not find PyTorch wheels for ROCm ${ROCM_TARGET} and Python ${PYTAG}."
        err "Check:  ${ROCM_AI_REPO}/rocm/manylinux/rocm-rel-${ROCM_TARGET}/"
        [ -n "$backup" ] && {
            err "Restoring your previous environment."
            rm -rf "$venv"
            mv "$backup" "$venv"
        }
        return 1
    fi

    local ROCM_REL TORCH_VERSION TORCH_WHEEL TORCHVISION_WHEEL TORCHAUDIO_WHEEL TRITON_WHEEL
    eval "$wheels"

    printf '       PyTorch %s · torchvision · torchaudio · triton\n' "$TORCH_VERSION"

    local base="$ROCM_AI_REPO/rocm/manylinux/rocm-rel-${ROCM_REL}"
    local tmp
    tmp="$(mktemp -d /tmp/rocm-wheels.XXXXXX)"
    local fail=0

    local w
    for w in "$TORCH_WHEEL" "$TORCHVISION_WHEEL" "$TORCHAUDIO_WHEEL" "$TRITON_WHEEL"; do
        # '+' must be percent-encoded in the URL path.
        local url="${base}/${w//+/%2B}"
        printf '       downloading %s ...\n' "$(printf '%s' "$w" | cut -c1-58)"
        if ! wget -q "$url" -O "$tmp/$w"; then
            err "Download failed: $url"
            fail=1
            break
        fi
    done

    if [ "$fail" = "1" ]; then
        rm -rf "$tmp"
        err "Wheel download failed. Your connection may have dropped."
        [ -n "$backup" ] && err "Previous environment preserved at $backup"
        return 1
    fi

    log "Installing PyTorch (this takes a few minutes)"
    pip install --no-cache-dir "$tmp/$TORCH_WHEEL" "$tmp/$TORCHVISION_WHEEL" \
        "$tmp/$TORCHAUDIO_WHEEL" "$tmp/$TRITON_WHEEL" || {
            err "PyTorch installation failed."
            rm -rf "$tmp"
            return 1
        }
    rm -rf "$tmp"

    # SageAttention is optional; its absence must never fail an upgrade.
    pip install --no-cache-dir sageattention >/dev/null 2>&1 \
        && log "SageAttention installed" \
        || warn "SageAttention not installed (optional — see docs/PERFORMANCE.md)"

    # --- WSL HSA runtime fix --------------------------------------------------
    # The wheel bundles an HSA runtime that conflicts with the one ROCDXG needs.
    local loc torch_lib
    loc="$(pip show torch 2>/dev/null | awk -F ': ' '/^Location/{print $2}')"
    torch_lib="$loc/torch/lib"
    if [ -n "$loc" ] && [ -d "$torch_lib" ]; then
        rm -f "$torch_lib"/libhsa-runtime64.so* 2>/dev/null
        log "Applied the WSL HSA runtime fix"
    fi

    # --- venv activation ------------------------------------------------------
    # Deliberately minimal: the launcher supplies the real environment, and
    # PYTORCH_HIP_ALLOC_CONF must never appear here again.
    {
        printf '\nexport HSA_ENABLE_DXG_DETECTION=1\n'
        printf 'export PIP_USER=0\n'
    } >> "$venv/bin/activate"

    deactivate 2>/dev/null || true

    success "Environment rebuilt with PyTorch ${TORCH_VERSION}+rocm${ROCM_REL}"

    if [ -n "$backup" ]; then
        printf '\n       The previous environment is preserved at:\n'
        printf '         %s\n' "$backup"
        printf '       Delete it once you have confirmed everything works:\n'
        printf '         rm -rf %s\n' "$backup"
    fi

    rm -f "$ROCM_AI_CONFIG_DIR/.preflight" "$ROCM_AI_CONFIG_DIR/.engine_summary" 2>/dev/null
    return 0
}

# ==============================================================================
# Stage 8 — Tools
# ==============================================================================

reinstall_tools() {
    headline "Reinstalling your AI tools' dependencies"

    # shellcheck disable=SC1091
    . "$TOOLKIT_ROOT/lib/launch.sh"
    # shellcheck disable=SC1091
    . "$TOOLKIT_ROOT/lib/tools.sh"

    local count=0 key name
    for key in $(rocm_ai_all_tool_keys); do
        rocm_ai_tool_installed "$key" || continue
        name="$(rocm_ai_tool_name "$key")"
        printf '\n  %s\n' "$name"

        local venv
        venv="$(rocm_ai_tool_venv "$key")"
        if [ ! -f "$HOME/$venv/bin/activate" ]; then
            warn "    environment '$venv' is missing — reinstall this tool from the menu"
            continue
        fi

        # shellcheck disable=SC1090
        . "$HOME/$venv/bin/activate"
        export PIP_USER=0

        if rocm_ai_install_deps "$key" 2>&1 | sed 's/^/    /'; then
            count=$((count + 1))
        else
            warn "    some dependencies could not be installed"
        fi

        # Custom nodes and extensions carry their own requirements, and they are
        # the usual source of "it worked before the upgrade" breakage. This was
        # missing from the upgrade path entirely: only the top-level requirements
        # file was reinstalled, so a machine with 19 custom nodes silently lost 48
        # packages, which later surfaced as ImportErrors inside workflows.
        rocm_ai_install_extension_deps "$key" 2>&1 | sed 's/^/    /'

        deactivate 2>/dev/null || true
    done

    printf '\n'
    if [ "$count" -eq 0 ]; then
        log "No installed tools needed dependency reinstalls."
    else
        success "Dependencies refreshed for $count tool(s)"
    fi
}

# ==============================================================================
# Stage 9 — Retune
# ==============================================================================

retune() {
    headline "Re-measuring performance for the new stack"

    printf '  Your previous performance profile was measured against ROCm %s.\n' "${ROCM_NOW:-?}"
    printf '  ROCm %s changes the GPU behaviour, so that profile is stale.\n\n' "$ROCM_TARGET"

    rm -f "$ROCM_AI_CONFIG_DIR/perf.env" "$ROCM_AI_CONFIG_DIR/perf_profile.json" 2>/dev/null

    if [ "$OPT_SKIP_RETUNE" = "1" ]; then
        log "Skipped. Run Performance -> Auto-tune from the menu when convenient."
        return 0
    fi

    if ! confirm_or_skip "Run the auto-tuner now? (a few minutes)"; then
        log "Skipped. Run Performance -> Auto-tune from the menu when convenient."
        return 0
    fi

    if [ -f "$TOOLKIT_ROOT/scripts/utils/auto_tuner.sh" ]; then
        bash "$TOOLKIT_ROOT/scripts/utils/auto_tuner.sh" || \
            warn "Tuning did not complete. You can re-run it from the menu."
    fi
}

# ==============================================================================
# Stage 10 — Verify
# ==============================================================================

verify() {
    headline "Verifying the upgrade"

    export HSA_ENABLE_DXG_DETECTION=1
    unset HSA_OVERRIDE_GFX_VERSION

    local py="$HOME/genai_env/bin/python3"
    local ok=1

    if [ -x "$py" ]; then
        if "$py" - <<'PY' 2>/dev/null
import sys
try:
    import torch
except Exception as exc:
    print("torch import failed:", exc)
    sys.exit(1)
if not torch.version.hip:
    print("no HIP support in this torch build")
    sys.exit(1)
if not torch.cuda.is_available():
    print("GPU not visible to PyTorch")
    sys.exit(1)
print("OK")
PY
        then
            success "PyTorch sees the GPU: $("$py" -c 'import torch; print(torch.cuda.get_device_name(0))' 2>/dev/null)"
        else
            warn "PyTorch cannot use the GPU yet."
            printf '\n'
            printf '       This is usually a pending WSL restart, and it is expected:\n\n'
            printf '         In Windows PowerShell:   wsl --shutdown\n'
            printf '         Then reopen Ubuntu and run:  ./menu.sh\n\n'
            printf '       If it persists after the restart, run:\n'
            printf '         ./menu.sh  ->  Settings  ->  GPU Diagnostics\n'
            ok=0
        fi
    else
        err "The Python environment is missing."
        ok=0
    fi

    printf '\n'
    printf '   Toolkit : v%s\n' "$(va_toolkit_local_version "$TOOLKIT_ROOT")"
    printf '   ROCm    : %s\n' "$(va_rocm_installed 2>/dev/null || echo unknown)"
    printf '   ROCDXG  : %s\n' "$(va_rocdxg_installed 2>/dev/null || echo unknown)"
    printf '   PyTorch : %s\n' "$(va_torch_installed "$py" 2>/dev/null || echo unknown)"
    printf '\n'
    printf '   Log: %s\n' "${LOG_FILE/#$HOME/\~}"
    printf '\n'
    return $((1 - ok))
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    detect_state
    plan_work

    if ! report_plan; then
        [ "$OPT_CHECK_ONLY" = "1" ] && return 0
    fi

    if [ "$OPT_CHECK_ONLY" = "1" ]; then
        printf '   Check only — nothing was changed.\n\n'
        return 0
    fi

    if ! confirm_or_skip "Proceed with the upgrade?"; then
        printf '\n   Cancelled. Nothing was changed.\n\n'
        return 0
    fi

    # Acquire root before the first download rather than midway through.
    if [ "${NEED_SUDO:-0}" = "1" ]; then
        if ! acquire_sudo; then
            printf '\n'
            err "Administrator rights are required, but sudo could not be used."
            printf '\n'
            printf '   This upgrade needs root to:\n'
            printf '     • install the ROCm packages\n'
            printf '     • build and install the ROCDXG GPU bridge\n'
            printf '     • install the login-shell GPU environment\n'
            printf '\n'
            if [ ! -t 0 ]; then
                printf '   There is no terminal here to enter a password in.\n'
                printf '   Run the upgrade from an interactive shell instead:\n'
                printf '\n'
                printf '       cd %s && ./upgrade.sh\n\n' "$TOOLKIT_ROOT"
            else
                printf '   Your sudo access did not grant a session. Check with:\n'
                printf '\n'
                printf '       sudo -v\n\n'
            fi
            printf '   Nothing has been changed. Re-run when ready.\n\n'
            return 1
        fi
        case "$SUDO_MODE" in
            cached)    log "Using your existing sudo session." ;;
            prompted)  success "Administrator rights acquired for this upgrade." ;;
        esac
    fi

    # 3. Toolkit first, so later stages use the newest code.
    if [ "$NEED_TOOLKIT" = "1" ]; then
        upgrade_toolkit || return 1
        reexec_if_updated
        detect_state
        plan_work
    fi

    # 4. Configuration migration — do this early so nothing downstream reads a
    #    harmful setting.
    if [ "$NEED_MIGRATE" = "1" ] || [ "$OPT_FORCE" = "1" ]; then
        run_migration
    fi

    # 5. Login-shell GPU environment.
    if [ "$NEED_SHELL" = "1" ] || [ "$OPT_FORCE" = "1" ]; then
        install_shell_env
    fi

    # 6. Remove the legacy stack, then install ROCm.
    #
    #    The teardown has to happen before the install: AMD requires the old
    #    packages gone, and both trees register /opt/rocm. It is also the one
    #    destructive step, so it runs as its own stage with its own typed
    #    confirmation rather than being folded into the install.
    if [ "${NEED_LEGACY_PURGE:-0}" = "1" ]; then
        remove_legacy_rocm || return 1
    fi

    if [ "$NEED_ROCM" = "1" ]; then
        upgrade_rocm || return 1
    else
        log "ROCm is already at ${ROCM_NOW} — skipping."
    fi

    if [ "$TARGET_CHANNEL" = "legacy" ] && [ "$NEED_ROCDXG" = "1" ]; then
        upgrade_rocdxg || warn "Continuing without rebuilding ROCDXG."
    elif [ "$TARGET_CHANNEL" != "legacy" ]; then
        log "librocdxg ships with ROCm ${ROCM_SERIES:-10.x} — no build step needed."
    fi

    # 7. Python environment.
    if [ "$NEED_ENV" = "1" ]; then
        rebuild_environment || return 1
    else
        log "PyTorch environment is current — skipping."
    fi

    # 8. Tool dependencies.
    if [ "$NEED_TOOLS" = "1" ]; then
        reinstall_tools
    fi

    # 9. Retune against the new stack.
    if [ "$NEED_ENV" = "1" ] || [ "$NEED_ROCM" = "1" ] || [ "$OPT_FORCE" = "1" ]; then
        retune
    fi

    # 10. Verify.
    verify
    local rc=$?

    printf '\n'
    if [ "$rc" -eq 0 ]; then
        if _rocm_ai_have_gum; then
            gum style --border rounded --margin "0 2" --padding "1 2" --border-foreground 46 \
                "$(gum style --bold --foreground 46 'Upgrade complete')" \
                "" \
                "ROCm $(va_rocm_installed 2>/dev/null || echo '?')  ·  PyTorch $(va_torch_installed "$HOME/genai_env/bin/python3" 2>/dev/null || echo '?')" \
                "" \
                "A WSL restart is required for the ROCm upgrade to take effect:" \
                "  In Windows PowerShell:  wsl --shutdown" \
                "  Then reopen Ubuntu and run:  ./menu.sh"
        else
            printf '=== Upgrade complete ===\n'
            printf 'Restart WSL to apply the ROCm changes:  wsl --shutdown\n'
        fi
    else
        warn "The upgrade finished, but the GPU is not usable yet."
        printf '\n'
        printf '   That is normal until WSL restarts. Run in PowerShell:\n\n'
        printf '       wsl --shutdown\n\n'
        printf '   Then reopen Ubuntu and run ./menu.sh\n'
    fi
    printf '\n'

    release_sudo
    return 0
}

main
