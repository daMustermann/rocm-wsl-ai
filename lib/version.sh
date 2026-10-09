#!/bin/bash
# ==============================================================================
# ROCm WSL AI Toolkit — Version discovery and comparison
# ==============================================================================
# Answers two questions, both without hardcoding anything that AMD changes:
#
#   1. What versions could be installed?  (queried from AMD's repositories)
#   2. What is installed right now, and is an upgrade worthwhile?
#
# Two release channels exist, and this file understands both.
#
#   core   (default, ROCm 10.x)  Built with AMD's "TheRock" system. Packages are
#          amdrocm10.1-gfx1100 from stable.repo.amd.com, installed under
#          /opt/rocm/core-10.1. PyTorch is not a hand-downloaded wheel any more:
#          it is resolved by pip from AMD's index using a device extra —
#              pip install --index-url <index>/ "torch[device-gfx1100]"
#          librocdxg, the WSL GPU bridge, SHIPS INSIDE ROCm here and is loaded
#          automatically when /dev/dxg exists. The Windows SDK is not needed.
#
#   legacy (ROCm <= 7.2.4)       Packages are `rocm` from repo.radeon.com,
#          installed under /opt/rocm-7.2. PyTorch wheels are named files scraped
#          from a flat manylinux directory, and librocdxg has to be BUILT from
#          source against the Windows SDK. Reachable via `upgrade.sh --target
#          legacy`, because WSL support in 10.x is still a technical preview.
#
# Nothing here is pinned to a specific wheel filename. Those filenames embed a
# git hash, so every ROCm patch release used to invalidate the installer until
# someone edited a script by hand.
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

# ROCm 10.x — TheRock package streams.
ROCM_AI_REPO_CORE="https://stable.repo.amd.com/rocm"
ROCM_AI_WHL_INDEX="${ROCM_AI_WHL_INDEX:-$ROCM_AI_REPO_CORE/whl-next/}"
ROCM_AI_AMD_GPG_KEY="${ROCM_AI_AMD_GPG_KEY:-$ROCM_AI_REPO_CORE/gpg/packages.gpg}"

# ROCm 7.2.x and older — legacy streams.
ROCM_AI_REPO="https://repo.radeon.com"
ROCM_AI_GITHUB_API="https://api.github.com"

# Fallbacks used when the network is unavailable. Kept in one place so they are
# easy to bump; they are deliberately conservative rather than bleeding edge.
ROCM_AI_FALLBACK_ROCM="7.2.4"
ROCM_AI_FALLBACK_LIBROCDXG="v1.2.2"
ROCM_AI_FALLBACK_SERIES="10.1"
ROCM_AI_FALLBACK_ROCM_VERSION="10.1.0"

# Which release stream to work against. Overridable from the environment so a
# user (or upgrade.sh --target) can pin a channel for one invocation.
ROCM_AI_CHANNEL="${ROCM_AI_CHANNEL:-core}"

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

# --- Installed state --------------------------------------------------------

# Which ROCm layout is on this machine: "core", "legacy", "both", or "none".
#
#   core   installs under /opt/rocm/core-<series>, e.g. /opt/rocm/core-10.1
#   legacy installs under /opt/rocm-<version>,  e.g. /opt/rocm-7.2.4
#
# A machine can legitimately have both for a while — that is exactly the state an
# interrupted upgrade leaves behind, and the caller has to be able to report it
# rather than silently prefer one.
va_install_kind() {
    local core legacy
    core="$(ls -d /opt/rocm/core-* 2>/dev/null | sort -V | tail -1)"
    # `.retired-<stamp>` directories are what remove_legacy_rocm renames the old
    # stack into. They must not count as an active install: they match a naive
    # `/opt/rocm-[0-9]*` glob because the version digits come first, and treating
    # them as present would report a legacy stack forever and offer the
    # destructive purge again on every subsequent upgrade.
    legacy="$(ls -d /opt/rocm-[0-9]* 2>/dev/null | grep -v '\.retired-' | sort -V | tail -1)"

    if [ -n "$core" ] && [ -n "$legacy" ]; then
        printf 'both'
    elif [ -n "$core" ]; then
        printf 'core'
    elif [ -n "$legacy" ]; then
        printf 'legacy'
    else
        printf 'none'
    fi
}

# Version string of whatever ROCm is installed, regardless of layout: 10.1.0 on
# a core install, 7.2.4 on a legacy one.
va_rocm_installed() {
    local f v core legacy

    for core in /opt/rocm/core-*; do
        [ -d "$core" ] || continue
        f="$core/.info/version"
        if [ -f "$f" ]; then
            v="$(tr -cd '0-9.' < "$f" | head -c 20)"
            [ -n "$v" ] && { printf '%s' "$v"; return 0; }
        fi
    done

    # /opt/rocm is an update-alternatives symlink on both channels, so reading
    # through it covers whichever layout is currently the alternative.
    if [ -f /opt/rocm/.info/version ]; then
        v="$(tr -cd '0-9.' < /opt/rocm/.info/version | head -c 20)"
        [ -n "$v" ] && { printf '%s' "$v"; return 0; }
    fi

    legacy="$(ls -d /opt/rocm-[0-9]* 2>/dev/null | grep -v '\.retired-' | sort -V | tail -1)"
    if [ -n "$legacy" ] && [ -f "$legacy/.info/version" ]; then
        v="$(tr -cd '0-9.' < "$legacy/.info/version" | head -c 20)"
        [ -n "$v" ] && { printf '%s' "$v"; return 0; }
    fi

    # Last resort: the Debian package version. The package name differs per
    # channel, and on a core install it is the meta package that carries the
    # series rather than any single component.
    dpkg-query -W -f='${Version}\n' 'amdrocm*' 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1
}

va_rocdxg_installed() {
    local candidate target
    # ROCm 10.x ships librocdxg in its own artifacts under the versioned prefix;
    # 7.2.x installed it into /opt/rocm/lib. Accept either.
    for candidate in /opt/rocm/core-*/lib/librocdxg.so /opt/rocm/lib/librocdxg.so; do
        [ -e "$candidate" ] || continue
        target="$(readlink -f "$candidate" 2>/dev/null)"
        va_rocdxg_version_of "$target"
        return 0
    done
    return 1
}

# v1.2.0 from .../librocdxg.so.1.2.0
va_rocdxg_version_of() {
    local path="$1" base
    [ -n "$path" ] || return 1
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

# shellcheck disable=SC2120  # args come from setup_pytorch_rocm.sh, menu.sh, upgrade.sh
va_python_tag() {
    # cp310 / cp312 — must match the interpreter that will run PyTorch.
    #
    # The argument is optional and defaults to python3, but callers pass an
    # explicit interpreter everywhere it matters, because the tag has to match
    # the interpreter that will import PyTorch rather than whatever happens to
    # be first on PATH:
    #     va_python_tag "$PYTHON_BIN"      # setup_pytorch_rocm.sh
    #     va_python_tag "$VENV_PY"         # upgrade.sh
    #     va_python_tag "$(command -v python3)"   # update_ai_setup.sh
    #
    # The "references arguments but none are ever passed" warning fires on
    # ShellCheck 0.8-0.9 because those callers live in other files and it
    # analyses one file at a time. 0.10+ suppresses it when the parameter has a
    # default, which is why CI (0.9) and a current local binary disagree.
    # Disabled here rather than in the CI -e list, so that a genuinely
    # argument-less function elsewhere in the tree still fails the build.
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

# The path segment AMD uses for this Ubuntu release. AMD publishes under
# ubuntu2204 / ubuntu2404 / ubuntu2604 rather than under codenames, so the
# mapping is explicit and an unrecognised release yields nothing at all. Empty is
# a deliberate answer: it means "we do not know this is supported", and callers
# must refuse rather than guess a URL.
va_ubuntu_repo_tag() {
    case "$(va_ubuntu_codename)" in
        jammy)    printf 'ubuntu2204' ;;
        noble)    printf 'ubuntu2404' ;;
        resolute) printf 'ubuntu2604' ;;
        *)        printf '' ;;
    esac
}

# --- Remote discovery -------------------------------------------------------

# ---- ROCm 10.x (TheRock) ---------------------------------------------------

# The apt base URI for this machine, e.g.
#   https://stable.repo.amd.com/rocm/core/packages/ubuntu2204
# Empty when the Ubuntu release is not one AMD publishes for.
va_core_apt_base() {
    local tag
    tag="$(va_ubuntu_repo_tag)"
    [ -n "$tag" ] || return 1
    printf '%s/core/packages/%s' "$ROCM_AI_REPO_CORE" "$tag"
}

# The package index for this machine. Fetched once and cached; callers parse it
# for whatever they need (series, versions, available gfx targets).
va_core_packages_index() {
    local tag base
    tag="$(va_ubuntu_repo_tag)" || return 1
    base="$ROCM_AI_REPO_CORE/core/packages/$tag"
    local cached
    if cached="$(va_cache_get "core_packages_${tag}" 21600)"; then
        printf '%s' "$cached"
        return 0
    fi
    local gz
    gz="$(_va_curl "$base/dists/stable/main/binary-amd64/Packages.gz")" || return 1
    [ -n "$gz" ] || return 1
    local plain
    plain="$(printf '%s' "$gz" | gunzip 2>/dev/null)" || return 1
    [ -n "$plain" ] || return 1
    va_cache_put "core_packages_${tag}" "$plain"
    printf '%s' "$plain"
}

# Newest ROCm 10.x series available for this Ubuntu release: "10.1".
#
# The meta package carries the series in its own name — amdrocm10.1 — while its
# per-architecture variants are amdrocm10.1-gfx1100 and its components are
# amdrocm-blas10.1. Matching the bare name exactly is what keeps a component
# name or an older series from being mistaken for the newest one.
va_latest_core_series() {
    local cached
    if cached="$(va_cache_get "latest_core_series")"; then
        printf '%s' "$cached"
        return 0
    fi

    local index series best=""
    index="$(va_core_packages_index 2>/dev/null)" || index=""
    if [ -n "$index" ]; then
        best="$(printf '%s\n' "$index" \
            | grep -oE '^Package: amdrocm[0-9]+\.[0-9]+$' \
            | sed -E 's/^Package: amdrocm//' \
            | sort -uV | tail -1)"
    fi

    [ -z "$best" ] && best="$ROCM_AI_FALLBACK_SERIES"
    va_cache_put "latest_core_series" "$best"
    printf '%s' "$best"
}

# Full version behind a series, from the meta package's Version field: 10.1.0
# (the Debian revision, e.g. 10.1.0-3, is dropped because pip wants x.y.z).
va_core_version_of_series() {
    local series="$1" index
    index="$(va_core_packages_index 2>/dev/null)" || index=""
    if [ -n "$index" ]; then
        local v
        v="$(printf '%s\n' "$index" \
            | grep -A3 -E "^Package: amdrocm${series//./\\.}\$" \
            | grep -oE '^Version: [0-9]+\.[0-9]+\.[0-9]+' \
            | head -1 | awk '{print $2}')"
        [ -n "$v" ] && { printf '%s' "$v"; return 0; }
    fi
    printf '%s' "$ROCM_AI_FALLBACK_ROCM_VERSION"
}

# The apt meta package to install for a series, optionally scoped to one GPU
# architecture:  amdrocm10.1  or  amdrocm10.1-gfx1100
va_core_meta_package() {
    local series="${1:-$ROCM_AI_FALLBACK_SERIES}" gfx="${2:-}"
    if [ -n "$gfx" ]; then
        printf 'amdrocm%s-gfx%s' "$series" "${gfx#gfx}"
    else
        printf 'amdrocm%s' "$series"
    fi
}

# The deb822 apt source stanza AMD documents, for this machine's release.
# Printed to stdout; callers write it under sudo.
va_core_apt_source() {
    local base
    base="$(va_core_apt_base)" || return 1
    cat <<EOF
X-Repo-Id: amdrocm-stable
Types: deb
URIs: ${base}/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/amdrocm.gpg
Enabled: yes
EOF
}

# GPU architectures ROCm 10.x publishes a per-GPU package for. Consumer parts
# only — the toolkit targets Radeon and Ryzen, never Instinct.
va_supported_gfx_targets() {
    local index
    index="$(va_core_packages_index 2>/dev/null)" || index=""
    if [ -n "$index" ]; then
        printf '%s\n' "$index" \
            | grep -oE '^Package: amdrocm[0-9]+\.[0-9]+-gfx[0-9a-z]+$' \
            | sed -E 's/.*-gfx//' | sort -u
        return 0
    fi
    # Offline fallback: the Radeon and Ryzen targets from the 10.1 matrix.
    printf '%s\n' gfx1030 gfx1100 gfx1101 gfx1102 gfx1103 \
                     gfx1150 gfx1151 gfx1152 gfx1153 gfx1200 gfx1201
}

# Detect the GPU's gfx target without needing ROCm to be installed yet.
#
# Order matters. A recorded choice wins, because a user who installed for
# gfx1100 should keep getting gfx1100 even if a second GPU appears later. Then
# an existing ROCm install, which can be asked directly. `rocm-bootstrap` is
# AMD's own detection helper and is used when nothing else is available.
va_gfx_detect() {
    if [ -n "${AMDROCM_DEVICE_TARGET:-}" ]; then
        printf '%s' "${AMDROCM_DEVICE_TARGET#gfx}"
        return 0
    fi

    local gfx
    gfx="$(rocminfo 2>/dev/null | grep -oE 'Name:[[:space:]]+gfx[0-9a-z]+' \
            | awk '{print $2}' | head -1)"
    if [ -n "$gfx" ]; then
        printf '%s' "${gfx#gfx}"
        return 0
    fi

    if command -v rocm-bootstrap-detect >/dev/null 2>&1; then
        gfx="$(rocm-bootstrap-detect 2>/dev/null | head -1)"
        case "$gfx" in
            gfx*) printf '%s' "${gfx#gfx}"; return 0 ;;
        esac
    fi

    return 1
}

# ---- PyTorch on ROCm 10.x --------------------------------------------------
#
# AMD's stable index is a PEP 503 tree: <index>/<project>/ lists that project's
# wheels. PyTorch wheels are named
#   torch-2.14.0+rocm10.1.0-cp310-cp310-linux_x86_64.whl
# so the ROCm release and the Python tag are both readable off the filename, and
# pip then resolves everything else — including the `rocm` sdist meta package
# that carries the [device-*] extras. That is why nothing here downloads a wheel
# by hand.

# Newest torch version published for a Python tag, restricted to a ROCm release.
#   va_latest_torch [cp310] [10.1]
#
# The local version in the wheel name carries the full ROCm version, not the
# series: a 10.1 wheel is built as +rocm10.1.0, so the series has to be followed
# by a dot and another component. Matching "+rocm10.1-" finds nothing at all.
va_latest_torch() {
    local pytag="${1:-$(va_python_tag)}" series="${2:-}"
    local cache_key="latest_torch_${pytag}_${series:-any}"

    local cached
    if cached="$(va_cache_get "$cache_key")"; then
        printf '%s' "$cached"
        return 0
    fi

    local html decoded best=""
    html="$(_va_curl "${ROCM_AI_WHL_INDEX}torch/")" || html=""
    if [ -n "$html" ]; then
        decoded="$(printf '%s' "$html" | sed -e 's/%2B/+/g' -e 's/&amp;/\&/g')"
        local rocmpat='rocm[0-9]+\.[0-9]+\.[0-9]+'
        [ -n "$series" ] && rocmpat="rocm${series//./\\.}\.[0-9]+"

        best="$(printf '%s' "$decoded" \
            | grep -oE "torch-[0-9]+\.[0-9]+\.[0-9]+\+${rocmpat}-${pytag}-${pytag}-linux_x86_64\.whl" \
            | grep -oE '^torch-[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^torch-//' \
            | sort -uV | tail -1)"
    fi

    [ -z "$best" ] && return 1
    va_cache_put "$cache_key" "$best"
    printf '%s' "$best"
}

# Confirm a series actually has torch wheels for this interpreter, and report the
# newest torch for it. Prints "<series> <torch>" or fails.
#
# This is the guard that replaced "pick the newest ROCm that has a repository".
# A series can be published for apt days before its wheels land for a given
# Python version, and installing it would leave a machine with no PyTorch at all.
va_core_series_with_wheels() {
    local pytag="${1:-$(va_python_tag)}"
    local series t
    while IFS= read -r series; do
        [ -n "$series" ] || continue
        if t="$(va_latest_torch "$pytag" "$series")"; then
            printf '%s %s' "$series" "$t"
            return 0
        fi
    done <<EOF
$(va_latest_core_series)
$ROCM_AI_FALLBACK_SERIES
EOF
    return 1
}

# Everything the installer needs to populate a virtual environment, as
# KEY=VALUE lines for eval. Prints nothing and fails when the index cannot be
# read or the device target is unknown.
#
#   va_resolve_torch_spec [gfx] [pytag] [series]
va_resolve_torch_spec() {
    local gfx="${1:-}" pytag="${2:-$(va_python_tag)}" series="${3:-}"

    if [ -z "$series" ]; then
        local pair
        pair="$(va_core_series_with_wheels "$pytag")" || return 1
        series="${pair%% *}"
    fi

    local rocm_ver
    rocm_ver="$(va_core_version_of_series "$series")"

    # A torch build has to exist for this series AND this interpreter. Without
    # this check the spec below would name a version that cannot be installed.
    local torch_ver
    torch_ver="$(va_latest_torch "$pytag" "$series")" || return 1

    # With no detectable GPU the per-architecture extra cannot be named, so fall
    # back to device-all rather than guessing one architecture.
    local device="all"
    [ -n "$gfx" ] && device="gfx${gfx#gfx}"

    printf 'CHANNEL=core\n'
    printf 'ROCM_SERIES=%s\n' "$series"
    printf 'ROCM_VERSION=%s\n' "$rocm_ver"
    printf 'TORCH_VERSION=%s\n' "$torch_ver"
    printf 'PYTHON_TAG=%s\n' "$pytag"
    printf 'DEVICE_TARGET=%s\n' "$device"
    printf 'APT_META_PACKAGE=%s\n' "$(va_core_meta_package "$series" "")"
    printf 'PIP_INDEX=%s\n' "$ROCM_AI_WHL_INDEX"
    # Note the version pin on `rocm` but NOT on torch: rocm's version is the ROCm
    # series, so `torch==10.1.0` asks for a torch release that does not exist.
    printf 'PIP_SPEC_ROCM=%s\n' "rocm[libraries,device-${device}]==${rocm_ver}"
    printf 'PIP_SPEC_TORCH=%s\n' "torch[device-${device}]"
    printf 'PIP_SPEC_TORCHVISION=%s\n' "torchvision[device-${device}]"
    printf 'PIP_SPEC_TORCHAUDIO=%s\n' "torchaudio"
    return 0
}

# ---- Channel dispatch ------------------------------------------------------

# Newest ROCm release available for this machine, honouring ROCM_AI_CHANNEL.
#
# "core"   prints the series, e.g. 10.1
# "legacy" prints the old-style full version, e.g. 7.2.4
#
# Existing callers compare this against va_rocm_installed with va_lt, which
# handles both shapes: 10.1 < 10.2 and 7.2.4 < 8.0.1 both sort correctly.
va_latest_rocm() {
    if [ "$ROCM_AI_CHANNEL" = "legacy" ]; then
        va_latest_legacy_rocm
        return $?
    fi
    va_latest_core_series
}

# ---- ROCm 7.2.x and older (legacy stream) ----------------------------------
# Everything below this line serves the legacy channel only. It is reachable via
# `upgrade.sh --target legacy` and exists because WSL support in ROCm 10.x is a
# technical preview; it is not the default path.

# Newest librocdxg release tag (the WSL GPU bridge).
#
# Only the legacy channel needs this. ROCm 10.x ships librocdxg inside its own
# artifacts and the ROCr runtime loads it automatically when /dev/dxg exists, so
# there is no separate library version to discover or build. The upstream
# librocdxg repository is also now deprecated — its source moved into
# ROCm/rocm-systems — but the tagged releases remain published, which is what a
# legacy rebuild uses.
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

# Newest legacy ROCm release that has an apt repository for this Ubuntu release.
#
# SC2120 for the same cross-file reason as va_python_tag: upgrade.sh passes
# "$CODENAME" explicitly, while the only call inside this file takes none.
# shellcheck disable=SC2120
va_latest_legacy_rocm() {
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

# Resolve the exact PyTorch wheel filenames for a legacy ROCm release and Python
# tag. Prints KEY=VALUE lines so the caller can eval them:
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
    local torch_t vision_t audio_t triton_t
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