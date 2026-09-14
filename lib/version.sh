#!/bin/bash
# ==============================================================================
# ROCm WSL AI Toolkit — Version discovery and comparison
# ==============================================================================
# Answers two questions, both without hardcoding anything that AMD changes:
#
#   1. What versions could be installed?  (queried from AMD's repositories)
#   2. What is installed right now, and is an upgrade worthwhile?
#
# The previous approach baked exact wheel filenames like
#   torch-2.9.1+rocm7.2.3.lw.gitebc02d69-cp310-cp310-linux_x86_64.whl
# into the installer. Those filenames embed a git hash, so every ROCm patch
# release invalidated the installer until someone edited the script by hand.
# AMD publishes a directory index, so the resolvers below read it and match the
# correct wheel for the running Python version.
#
# Network results are cached, and every resolver has an offline fallback, so the
# toolkit still works on a machine with no connectivity.
# ==============================================================================

if [ -n "${_ROCM_AI_VERSION_LOADED:-}" ]; then
    return 0 2>/dev/null || true
fi
_ROCM_AI_VERSION_LOADED=1

ROCM_AI_CACHE_DIR="${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}/cache"
ROCM_AI_UPSTREAM_CACHE_TTL="${ROCM_AI_UPSTREAM_CACHE_TTL:-86400}"   # 24h
ROCM_AI_REPO="https://repo.radeon.com"
ROCM_AI_GITHUB_API="https://api.github.com"

# Fallbacks used when the network is unavailable. Kept in one place so they are
# easy to bump; they are deliberately conservative rather than bleeding edge.
ROCM_AI_FALLBACK_ROCM="7.2.4"
ROCM_AI_FALLBACK_LIBROCDXG="v1.2.2"

_va_curl() { curl -fsSL --max-time "${ROCM_AI_HTTP_TIMEOUT:-25}" "$@" 2>/dev/null; }

# --- Cache helpers -----------------------------------------------------------

# va_cache_get <key> <ttl-seconds> -> prints cached value if fresh
va_cache_get() {
    local key="$1" ttl="${2:-$ROCM_AI_UPSTREAM_CACHE_TTL}"
    local file="$ROCM_AI_CACHE_DIR/$key"
    [ -f "$file" ] || return 1
    local now age
    now="$(date +%s)"
    age=$(( now - $(stat -c %Y "$file" 2>/dev/null || echo 0) ))
    [ "$age" -ge 0 ] && [ "$age" -lt "$ttl" ] || return 1
    cat "$file"
}

va_cache_put() {
    local key="$1" value="$2"
    mkdir -p "$ROCM_AI_CACHE_DIR" 2>/dev/null || return 0
    printf '%s' "$value" > "$ROCM_AI_CACHE_DIR/$key" 2>/dev/null || true
}

# --- Version comparison ------------------------------------------------------
# Pure-bash; returns 0 when $1 < $2, so it reads like a normal test.

va_lt() {
    [ "$1" = "$2" ] && return 1
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}

va_ge() { ! va_lt "$1" "$2"; }

va_gt() { va_lt "$2" "$1"; }

# --- Installed state --------------------------------------------------------

va_rocm_installed() {
    if [ -f /opt/rocm/.info/version ]; then
        tr -cd '0-9.' < /opt/rocm/.info/version | head -c 20
        return 0
    fi
    command -v rocminfo >/dev/null 2>&1 || return 1
    # Fall back to the package version when the version file is absent.
    dpkg-query -W -f='${Version}' rocm-core 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+'
}

va_rocdxg_installed() {
    [ -f /opt/rocm/lib/librocdxg.so ] || return 1
    local target
    target="$(readlink -f /opt/rocm/lib/librocdxg.so 2>/dev/null)"
    va_rocdxg_version_of "$target"
}

# v1.2.0 from .../librocdxg.so.1.2.0
va_rocdxg_version_of() {
    local path="$1" base
    base="$(basename "$path")"
    # librocdxg.so.1.2.0  or  librocdxg.so.1
    printf '%s' "$base" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

va_torch_installed() {
    local py="${1:-$HOME/genai_env/bin/python3}"
    [ -x "$py" ] || return 1
    "$py" -c 'import torch; print(torch.__version__)' 2>/dev/null
}

va_torch_hip_version() {
    local py="${1:-$HOME/genai_env/bin/python3}"
    [ -x "$py" ] || return 1
    "$py" -c 'import torch; print(torch.version.hip or "")' 2>/dev/null
}

va_python_tag() {
    # cp310 / cp312 — must match the interpreter that will run PyTorch.
    local py="${1:-python3}"
    "$py" -c 'import sys; print("cp%d%d" % sys.version_info[:2])' 2>/dev/null
}

va_python_version() {
    local py="${1:-python3}"
    "$py" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null
}

va_ubuntu_codename() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        printf '%s' "${VERSION_CODENAME:-unknown}"
    else
        lsb_release -cs 2>/dev/null || echo unknown
    fi
}

# --- Remote discovery -------------------------------------------------------

# Newest ROCm release that has an apt repository for this Ubuntu release.
va_latest_rocm() {
    local codename="${1:-$(va_ubuntu_codename)}"
    local cache_key="latest_rocm_${codename}"

    local cached
    if cached="$(va_cache_get "$cache_key")" && [ -n "$cached" ]; then
        printf '%s' "$cached"
        return 0
    fi

    local html versions best=""
    html="$(_va_curl "$ROCM_AI_REPO/rocm/apt/")" || true
    if [ -n "$html" ]; then
        # Only stable x.y.z entries; skip alpha/beta/rc directories.
        versions="$(printf '%s' "$html" \
            | grep -oE 'href="[0-9]+\.[0-9]+(\.[0-9]+)?/"' \
            | sed 's/href="//;s/\/"//' \
            | grep -vE 'alpha|beta|rc' \
            | sort -uV)"

        # Walk newest-first and take the first release that actually publishes
        # a dist for this codename. Directory presence alone is not enough.
        local v
        while IFS= read -r v; do
            [ -z "$v" ] && continue
            if _va_curl -o /dev/null "$ROCM_AI_REPO/rocm/apt/${v}/dists/${codename}/Release"; then
                best="$v"
                break
            fi
        done <<< "$(printf '%s\n' "$versions" | tac)"
    fi

    [ -z "$best" ] && best="$ROCM_AI_FALLBACK_ROCM"
    va_cache_put "$cache_key" "$best"
    printf '%s' "$best"
}

# Newest librocdxg release tag (the WSL GPU bridge).
va_latest_librocdxg() {
    local cache_key="latest_librocdxg"
    local cached
    if cached="$(va_cache_get "$cache_key")" && [ -n "$cached" ]; then
        printf '%s' "$cached"
        return 0
    fi

    local tags best=""
    tags="$(_va_curl "$ROCM_AI_GITHUB_API/repos/ROCm/librocdxg/tags?per_page=30")" || true
    if [ -n "$tags" ]; then
        best="$(printf '%s' "$tags" \
            | grep -oE '"name"[[:space:]]*:[[:space:]]*"v?[0-9][^"]*"' \
            | sed 's/.*"\(v\?[0-9][^"]*\)"/\1/' \
            | sort -uV | tail -1)"
    fi

    [ -z "$best" ] && best="$ROCM_AI_FALLBACK_LIBROCDXG"
    va_cache_put "$cache_key" "$best"
    printf '%s' "$best"
}

# Resolve the exact PyTorch wheel filenames for a ROCm release and Python tag.
# Prints KEY=VALUE lines so the caller can eval them:
#   TORCH_WHEEL=...  TORCHVISION_WHEEL=...  TORCHAUDIO_WHEEL=...  TRITON_WHEEL=...
#   TORCH_VERSION=2.11.0  ROCM_REL=7.2.4
# Returns 1 if any required wheel cannot be found.
va_resolve_torch_wheels() {
    local rocm_rel="$1" pytag="$2"
    local base="$ROCM_AI_REPO/rocm/manylinux/rocm-rel-${rocm_rel}"

    local html
    html="$(_va_curl "$base/")" || return 1
    [ -n "$html" ] || return 1

    # Filenames are URL-encoded: %2B is '+'.
    local decoded
    decoded="$(printf '%s' "$html" | sed 's/%2B/+/g')"

    # Pick the newest version of each package for this Python tag.
    local torch_t torchv vision_t audio_t triton_t
    torch_t="$(printf '%s' "$decoded" \
        | grep -oE "torch-[0-9][^\"<>]*${pytag}-${pytag}-linux_x86_64\.whl" \
        | sort -uV | tail -1)"
    vision_t="$(printf '%s' "$decoded" \
        | grep -oE "torchvision-[0-9][^\"<>]*${pytag}-${pytag}-linux_x86_64\.whl" \
        | sort -uV | tail -1)"
    audio_t="$(printf '%s' "$decoded" \
        | grep -oE "torchaudio-[0-9][^\"<>]*${pytag}-${pytag}-linux_x86_64\.whl" \
        | sort -uV | tail -1)"
    triton_t="$(printf '%s' "$decoded" \
        | grep -oE "triton-[0-9][^\"<>]*${pytag}-${pytag}-linux_x86_64\.whl" \
        | sort -uV | tail -1)"

    [ -n "$torch_t" ] || return 1
    [ -n "$vision_t" ] || return 1
    [ -n "$audio_t" ] || return 1
    [ -n "$triton_t" ] || return 1

    local torch_ver
    torch_ver="$(printf '%s' "$torch_t" | grep -oE '^torch-[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^torch-//')"

    printf 'ROCM_REL=%s\n' "$rocm_rel"
    printf 'TORCH_VERSION=%s\n' "$torch_ver"
    printf 'TORCH_WHEEL=%s\n' "$torch_t"
    printf 'TORCHVISION_WHEEL=%s\n' "$vision_t"
    printf 'TORCHAUDIO_WHEEL=%s\n' "$audio_t"
    printf 'TRITON_WHEEL=%s\n' "$triton_t"
    return 0
}

# Newest ROCm release for which we can resolve working wheels for this Python.
# Guards against a ROCm release that exists as a package but has no wheels yet.
va_best_installable_rocm() {
    local pytag="$1"
    local cache_key="best_installable_${pytag}"
    local cached
    if cached="$(va_cache_get "$cache_key")" && [ -n "$cached" ]; then
        printf '%s' "$cached"
        return 0
    fi

    local versions best=""
    local html
    html="$(_va_curl "$ROCM_AI_REPO/rocm/manylinux/")" || true
    if [ -n "$html" ]; then
        versions="$(printf '%s' "$html" \
            | grep -oE 'href="rocm-rel-[0-9][^"]*/"' \
            | sed 's/href="rocm-rel-//;s/\/"//' \
            | sort -uV)"
        local v
        while IFS= read -r v; do
            [ -z "$v" ] && continue
            if va_resolve_torch_wheels "$v" "$pytag" >/dev/null 2>&1; then
                best="$v"
                break
            fi
        done <<< "$(printf '%s\n' "$versions" | tac)"
    fi

    [ -z "$best" ] && best="$ROCM_AI_FALLBACK_ROCM"
    va_cache_put "$cache_key" "$best"
    printf '%s' "$best"
}

# --- Toolkit version --------------------------------------------------------

# The version recorded in the checkout, e.g. 4.1.0
va_toolkit_local_version() {
    local root="${1:-${TOOLKIT_ROOT:-.}}"
    if [ -f "$root/VERSION" ]; then
        tr -d ' \r\n' < "$root/VERSION"
    else
        echo "unknown"
    fi
}

# The version published on the remote's default branch. Uses `git show` against
# the already-fetched remote ref, so no extra network round trip beyond fetch.
va_toolkit_remote_version() {
    local root="${1:-${TOOLKIT_ROOT:-.}}" branch="${2:-main}"
    git -C "$root" show "origin/${branch}:VERSION" 2>/dev/null | tr -d ' \r\n'
}

# --- Machine-wide GPU environment ------------------------------------------
# The most common support question is "PyTorch cannot see my GPU", and the single
# cause behind most instances is that HSA_ENABLE_DXG_DETECTION must be set before
# the Python process starts. Version 3.x appended it to the virtualenv's activate
# script, so the GPU existed only inside an activated venv — invisible to an IDE,
# a Jupyter kernel, a cron job, or a plain `python3` in a fresh shell.
#
# Writing a profile.d drop-in makes the GPU environment part of a normal login
# shell, so the toolkit and everything else agree. It is optional, idempotent, and
# easily removed.

ROCM_AI_SHELL_ENV_FILE="${ROCM_AI_SHELL_ENV_FILE:-/etc/profile.d/rocm-wsl-ai.sh}"

# Emit the canonical environment block. Used both for the drop-in and for the
# toolkit's own env file.
rocm_ai_env_block() {
    local config_dir="${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}"
    cat <<EOF
# ROCm WSL2 AI Toolkit — GPU environment
# Generated automatically. Edit through the menu, not by hand.

# Required for ROCm to reach the GPU inside WSL2. Must be set before Python
# starts; without it libhsa reports zero GPU agents and torch sees no device.
export HSA_ENABLE_DXG_DETECTION=1

# With ROCDXG the GPU announces its own architecture. An override makes the
# runtime reject the device, so it must never be set.
unset HSA_OVERRIDE_GFX_VERSION

# Persist MIOpen's convolution tuning database. Without a stable path every
# launch re-searches for the best algorithm, costing seconds before the first
# image appears.
export MIOPEN_USER_DB_PATH="$config_dir/miopen"
export MIOPEN_CUSTOM_CACHE_DIR="$config_dir/miopen"
export MIOPEN_LOG_LEVEL=3
mkdir -p "\$MIOPEN_USER_DB_PATH" 2>/dev/null || true

# This variable segfaults torch 2.9.1+rocm7.2.3 during import. Older toolkit
# versions set it; make sure it can never leak into a Python process.
unset PYTORCH_HIP_ALLOC_CONF
EOF
}

rocm_ai_write_env_file() {
    local dir="${ROCM_AI_CONFIG_DIR:-$HOME/.config/rocm-wsl-ai}"
    mkdir -p "$dir" 2>/dev/null || return 1
    rocm_ai_env_block > "$dir/gpu_env.sh" 2>/dev/null || return 1
    printf '%s' "$dir/gpu_env.sh"
}

# Install the login-shell drop-in. Returns 0 when present afterwards.
rocm_ai_install_shell_integration() {
    local target="$ROCM_AI_SHELL_ENV_FILE"

    # Already correct?
    if [ -f "$target" ] && grep -q "ROCm WSL2 AI Toolkit" "$target" 2>/dev/null; then
        return 0
    fi

    local content
    content="$(rocm_ai_env_block)"

    # Prefer a system-wide drop-in so every login shell benefits.
    if [ -w /etc/profile.d ] 2>/dev/null; then
        printf '%s\n' "$content" > "$target" 2>/dev/null && return 0
    fi
    if command -v sudo >/dev/null 2>&1; then
        if printf '%s\n' "$content" | sudo tee "$target" >/dev/null 2>&1; then
            return 0
        fi
    fi

    # Fall back to the user's own profile, which still needs no sudo.
    local rc="$HOME/.bashrc"
    if [ -f "$rc" ] && ! grep -q "ROCm WSL2 AI Toolkit" "$rc" 2>/dev/null; then
        {
            printf '\n# --- ROCm WSL2 AI Toolkit ---\n'
            printf '%s\n' "$content"
        } >> "$rc" && return 0
    fi

    return 1
}

rocm_ai_shell_integration_present() {
    local target="$ROCM_AI_SHELL_ENV_FILE"
    if [ -f "$target" ] && grep -q "ROCm WSL2 AI Toolkit" "$target" 2>/dev/null; then
        return 0
    fi
    [ -f "$HOME/.bashrc" ] && grep -q "ROCm WSL2 AI Toolkit" "$HOME/.bashrc" 2>/dev/null
}

# --- Summary -----------------------------------------------------------------

va_summary() {
    local codename pytag
    codename="$(va_ubuntu_codename)"
    pytag="$(va_python_tag "$HOME/genai_env/bin/python3" 2>/dev/null || va_python_tag python3)"

    printf '  toolkit        : %s\n' "$(va_toolkit_local_version "${TOOLKIT_ROOT:-.}")"
    printf '  ubuntu         : %s (%s)\n' "$codename" "$(va_python_version "$HOME/genai_env/bin/python3" 2>/dev/null || echo '?')"
    printf '  python tag     : %s\n' "$pytag"
    printf '  ROCm installed : %s\n' "$(va_rocm_installed 2>/dev/null || echo 'not installed')"
    printf '  librocdxg      : %s\n' "$(va_rocdxg_installed 2>/dev/null || echo 'not installed')"
    printf '  PyTorch        : %s\n' "$(va_torch_installed 2>/dev/null || echo 'not installed')"
    printf '  ROCm newest    : %s (with wheels: %s)\n' \
        "$(va_latest_rocm "$codename")" "$(va_best_installable_rocm "$pytag")"
}
