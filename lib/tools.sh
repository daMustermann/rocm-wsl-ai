#!/bin/bash
# ==============================================================================
# ROCm WSL AI Toolkit — Tool Registry
# ==============================================================================
# A description of every tool the toolkit can install, update, launch and place
# on the Windows desktop. Everything else in the toolkit reads this list, so
# adding support for a new tool means adding one entry here.
#
# Registry format (one line per tool, pipe-separated):
#
#   key|Display Name|repo-url|install-dir|venv|launch-entry|port|kind|notes
#
#   key          stable identifier used by config files and shortcuts
#   repo-url     git remote, or "-" for tools that are not git clones
#   install-dir  absolute path, $HOME allowed
#   venv         "genai_env" (shared inference), "kohya_env", or "own"
#   launch-entry relative path to the file that must exist for the tool to count
#                as installed
#   port         default web port, or "-" for CLI-only tools
#   kind         "comfyui" | "webui" | "gradio" | "cli" | "custom"
#   notes        short description shown in the menu
#
# ------------------------------------------------------------------------------
# On third-party and "grey area" tools
# ------------------------------------------------------------------------------
# This file intentionally contains only tools that are openly hosted and widely
# distributed. It does NOT list face-swap or likeness-manipulation applications,
# even though the toolkit can install and run them perfectly well.
#
# That is a deliberate editorial choice, not a technical limitation:
#   * GitHub's Acceptable Use Policies prohibit non-consensual intimate imagery
#     and synthetic or manipulated media intended to mislead, which is why most
#     face-swap repositories were removed from GitHub.
#   * A repository that ships an installer for a named face-swap app tends to be
#     reported and taken down, regardless of the tool's legality.
#
# The generic mechanism is fully supported instead: see `rocm_ai_add_custom_tool`
# below, and docs/ADDING_TOOLS.md. A user can register ANY git repository —
# including one hosted on Codeberg — with a name of their choosing, and it gets
# cloning, dependency installation, launching, updating, and a desktop shortcut,
# exactly like a built-in tool. The user's own registry lives in
# ~/.config/rocm-wsl-ai/tools.local, which is gitignored and never committed.
# ==============================================================================

# Built-in registry. Keep ordered roughly by how likely a new user is to want it.
ROCM_AI_TOOL_REGISTRY=(
    "comfyui|ComfyUI|https://github.com/comfyanonymous/ComfyUI.git|\$HOME/ComfyUI|genai_env|main.py|8188|comfyui|Node-based diffusion workflows. The recommended starting point."
    "sdnext|SD.Next|https://github.com/vladmandic/sdnext.git|\$HOME/SD.Next|genai_env|webui.sh|7860|webui|Feature-rich Stable Diffusion WebUI with strong AMD support."
    "automatic1111|Automatic1111|https://github.com/AUTOMATIC1111/stable-diffusion-webui.git|\$HOME/stable-diffusion-webui|genai_env|webui.sh|7860|webui|The original Stable Diffusion WebUI. Huge extension ecosystem."
    "kohya_ss|kohya_ss (training)|https://github.com/bmaltais/kohya_ss.git|\$HOME/kohya_ss|kohya_env|kohya_gui.py|7861|gradio|LoRA, DreamBooth and fine-tuning. Uses its own venv."
    "textgen|Text Generation WebUI|https://github.com/oobabooga/text-generation-webui.git|\$HOME/text-generation-webui|genai_env|server.py|5000|webui|Local LLM chat and text generation."
)

# --- Registry parsing ---------------------------------------------------------

# rocm_ai_registry_row <key> -> prints the registry line, or nothing.
rocm_ai_registry_row() {
    local want="$1" row
    for row in "${ROCM_AI_TOOL_REGISTRY[@]}"; do
        [ "${row%%|*}" = "$want" ] && { printf '%s' "$row"; return 0; }
    done
    return 1
}

# rocm_ai_registry_field <key> <field-name>
#   field-name: name repo dir venv entry port kind notes
rocm_ai_registry_field() {
    local key="$1" field="$2" row
    row="$(rocm_ai_registry_row "$key")" || return 1
    local -a parts=()
    IFS='|' read -r -a parts <<< "$row"
    case "$field" in
        key)   printf '%s' "${parts[0]}" ;;
        name)  printf '%s' "${parts[1]}" ;;
        repo)  printf '%s' "${parts[2]}" ;;
        dir)   eval printf '%s' "\"${parts[3]}\"" ;;
        venv)  printf '%s' "${parts[4]}" ;;
        entry) printf '%s' "${parts[5]}" ;;
        port)  printf '%s' "${parts[6]}" ;;
        kind)  printf '%s' "${parts[7]}" ;;
        notes) printf '%s' "${parts[8]}" ;;
        *)     return 1 ;;
    esac
}

# All known keys: built-in registry plus the user's local additions.
rocm_ai_all_tool_keys() {
    local row
    for row in "${ROCM_AI_TOOL_REGISTRY[@]}"; do
        printf '%s\n' "${row%%|*}"
    done
    rocm_ai_local_tool_keys
}

rocm_ai_tool_name() { rocm_ai_registry_field "$1" name 2>/dev/null; }
rocm_ai_tool_dir()  { rocm_ai_registry_field "$1" dir  2>/dev/null; }
rocm_ai_tool_port() { rocm_ai_registry_field "$1" port 2>/dev/null; }

# Resolve the port for a tool, honouring the user's port overrides.
rocm_ai_tool_effective_port() {
    local key="$1" default_port
    default_port="$(rocm_ai_tool_port "$key")"
    case "$key" in
        comfyui)       printf '%s' "${COMFYUI_PORT:-${default_port}}" ;;
        sdnext)        printf '%s' "${SDNEXT_PORT:-${default_port}}" ;;
        automatic1111) printf '%s' "${A1111_PORT:-${default_port}}" ;;
        kohya_ss)      printf '%s' "${KOHYA_PORT:-${default_port}}" ;;
        textgen)       printf '%s' "${TEXTGEN_PORT:-${default_port}}" ;;
        *)             printf '%s' "$default_port" ;;
    esac
}

# Is the tool present on disk?
rocm_ai_tool_installed() {
    local key="$1" dir entry
    dir="$(rocm_ai_tool_dir "$key")" || return 1
    entry="$(rocm_ai_registry_field "$key" entry)"
    [ -n "$dir" ] || return 1
    if [ -n "$entry" ] && [ "$entry" != "-" ]; then
        [ -e "$dir/$entry" ]
    else
        [ -d "$dir" ]
    fi
}

# Which venv does this tool use, and does it exist?
rocm_ai_tool_venv() {
    local key="$1" venv
    venv="$(rocm_ai_registry_field "$key" venv)"
    [ "$venv" = "own" ] && venv="genai_env"
    printf '%s' "$venv"
}

# --- User-local tools (generic third-party support) ---------------------------
# Stored as one registry line per entry so the shell can read it without a JSON
# parser. Designed so that registering a tool from any host (GitHub, Codeberg,
# self-hosted git) is a first-class operation.

ROCM_AI_LOCAL_TOOLS="$ROCM_AI_CONFIG_DIR/tools.local"

rocm_ai_local_tool_keys() {
    [ -f "$ROCM_AI_LOCAL_TOOLS" ] || return 0
    while IFS= read -r line; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        printf '%s\n' "${line%%|*}"
    done < "$ROCM_AI_LOCAL_TOOLS"
}

rocm_ai_local_tool_row() {
    local want="$1" line
    [ -f "$ROCM_AI_LOCAL_TOOLS" ] || return 1
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        [ "${line%%|*}" = "$want" ] && { printf '%s' "$line"; return 0; }
    done < "$ROCM_AI_LOCAL_TOOLS"
    return 1
}

# Override the built-in lookup so local tools participate everywhere.
rocm_ai_registry_row() {
    local want="$1" row
    for row in "${ROCM_AI_TOOL_REGISTRY[@]}"; do
        [ "${row%%|*}" = "$want" ] && { printf '%s' "$row"; return 0; }
    done
    rocm_ai_local_tool_row "$want"
}

# rocm_ai_add_custom_tool
#   Interactive: register any git repository as a toolkit-managed tool.
rocm_ai_add_custom_tool() {
    clear
    ai_banner "Add a third-party tool"
    cat <<'EOF'
  Register any Git repository so the toolkit can install, launch, update and
  create a Windows desktop shortcut for it, exactly like a built-in tool.

  The repository may be hosted anywhere — GitHub, Codeberg, GitLab, or a private
  server. Nothing is sent anywhere; the entry is stored only on this machine in:

EOF
    printf '    %s\n\n' "$ROCM_AI_LOCAL_TOOLS"
    cat <<'EOF'
  You are responsible for complying with the licence and the laws that apply
  where you live, and for how you use the tool.
EOF
    echo ""

    local name repo_url dir_name entry port venv git_url

    read -rp "  Display name (e.g. 'My Tool'): " name
    [ -z "$name" ] && { ai_warn "Cancelled."; return 1; }

    read -rp "  Git repository URL: " repo_url
    [ -z "$repo_url" ] && { ai_warn "Cancelled."; return 1; }

    # Accept owner/repo shorthand for GitHub.
    if [[ "$repo_url" != *"://"* && "$repo_url" != git@* ]]; then
        git_url="https://github.com/${repo_url}.git"
        ai_dim "  Interpreting as: $git_url"
    else
        git_url="$repo_url"
    fi

    local default_dir
    default_dir="$HOME/$(basename "${git_url%.git}")"
    read -rp "  Install directory [$default_dir]: " dir_name
    dir_name="${dir_name:-$default_dir}"

    read -rp "  Command to run (relative to that directory, e.g. 'python app.py'): " entry
    [ -z "$entry" ] && { ai_warn "Cancelled."; return 1; }

    read -rp "  Web port (blank for none): " port
    port="${port:--}"

    read -rp "  Python venv to use [genai_env]: " venv
    venv="${venv:-genai_env}"

    # Derive a stable key from the display name.
    local key
    key="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_' | sed 's/_*$//')"
    [ -z "$key" ] && key="custom_tool"

    mkdir -p "$ROCM_AI_CONFIG_DIR"
    if rocm_ai_registry_row "$key" >/dev/null 2>&1; then
        ai_err "A tool with key '$key' already exists (from '$name')."
        return 1
    fi

    # entry holds the full command; dir holds the clone target.
    printf '%s|%s|%s|%s|%s|%s|%s|custom|User-registered third-party tool\n' \
        "$key" "$name" "$git_url" "$dir_name" "$venv" "$entry" "$port" \
        >> "$ROCM_AI_LOCAL_TOOLS"

    ai_ok "Registered '$name' as '$key'."
    ai_say "     Install it now from:  Install  ->  $name"
    return 0
}

# --- Install ------------------------------------------------------------------

rocm_ai_install_tool() {
    local key="$1"
    local name dir repo venv
    name="$(rocm_ai_tool_name "$key")" || { ai_err "Unknown tool '$key'"; return 1; }
    dir="$(rocm_ai_tool_dir "$key")"
    repo="$(rocm_ai_registry_field "$key" repo)"
    venv="$(rocm_ai_tool_venv "$key")"

    if rocm_ai_tool_installed "$key"; then
        ai_say ""
        ai_info "$name is already installed at $dir"
        if confirm "Update it instead?"; then
            rocm_ai_update_tool "$key"
        fi
        return 0
    fi

    ai_banner "Installing $name"

    if ! ai_require_venv "$venv"; then
        return 1
    fi

    # Clone
    if [ "$repo" != "-" ] && [ -n "$repo" ]; then
        if [ -d "$dir/.git" ]; then
            ai_info "Updating existing clone in $dir"
            git -C "$dir" pull --rebase --autostash || ai_warn "git pull had issues — continuing"
        else
            ai_info "Cloning $repo"
            mkdir -p "$(dirname "$dir")"
            git clone --depth=1 --recurse-submodules "$repo" "$dir" \
                || { ai_err "Clone failed. Check the URL and your connection."; return 1; }
        fi
        # Submodules are needed by kohya_ss and some ComfyUI nodes.
        if [ -f "$dir/.gitmodules" ]; then
            ai_info "Initialising submodules"
            git -C "$dir" submodule update --init --recursive \
                || ai_warn "Some submodules failed to initialise"
        fi
    else
        mkdir -p "$dir"
    fi

    # Python dependencies
    rocm_ai_install_deps "$key"

    ai_ok "$name installed."
    local port
    port="$(rocm_ai_tool_effective_port "$key")"
    [ "$port" != "-" ] && ai_say "     It will be available at http://localhost:$port when running."
    return 0
}

# Install a tool's Python requirements, never letting a dependency file replace
# the ROCm PyTorch build with the CUDA one from PyPI.
rocm_ai_install_deps() {
    local key="$1" dir
    dir="$(rocm_ai_tool_dir "$key")"
    [ -d "$dir" ] || return 1

    local -a reqs=()
    local candidate
    for candidate in requirements.txt requirements_linux.txt; do
        [ -f "$dir/$candidate" ] && reqs+=("$candidate")
    done

    if [ "${#reqs[@]}" -eq 0 ]; then
        ai_dim "  No requirements file found — nothing to install."
        return 0
    fi

    local req
    for req in "${reqs[@]}"; do
        ai_info "Installing Python dependencies from $req"
        rocm_ai_pip_filtered "$dir/$req" || ai_warn "Some packages in $req failed — continuing"
    done

    # kohya_ss keeps its training code in a submodule that must be installed.
    if [ -d "$dir/sd-scripts" ] && [ -f "$dir/sd-scripts/setup.py" ]; then
        ai_info "Installing kohya sd-scripts package"
        ( cd "$dir" && pip install -e ./sd-scripts ) || ai_warn "sd-scripts install failed"
    fi
    if [ "$key" = "kohya_ss" ]; then
        pip install "gradio>=5.34.1" >/dev/null 2>&1 || ai_warn "gradio install failed"
    fi
    return 0
}

# Strip torch/torchvision/torchaudio from a requirements file before handing it
# to pip. Without this, pip resolves torch from PyPI and silently replaces the
# ROCm wheels with the CUDA build (over a gigabyte of nvidia_* packages).
rocm_ai_pip_filtered() {
    local req_file="$1"
    [ -f "$req_file" ] || return 0

    local tmp
    tmp="$(mktemp -t rocm-ai-req.XXXXXX)"
    local skip='^[[:space:]]*(torch|torchvision|torchaudio|pytorch-triton-rocm)([>=<!;@# ]|$)|^[[:space:]]*-[[:space:]]*(e|--editable)[[:space:]]+.*sd-scripts'

    if grep -qE '^[[:space:]]*-[[:space:]]*r[[:space:]]+requirements\.txt' "$req_file"; then
        # kohya_ss style: an included file that itself pins torch.
        local base
        base="$(dirname "$req_file")"
        grep -ivE '^[[:space:]]*-[[:space:]]*r[[:space:]]+requirements\.txt' "$req_file" \
            | grep -ivE "$skip" > "$tmp"
        [ -f "$base/requirements.txt" ] && grep -ivE "$skip" "$base/requirements.txt" >> "$tmp"
    else
        grep -ivE "$skip" "$req_file" > "$tmp"
    fi

    if [ ! -s "$tmp" ]; then
        ai_dim "  All requirements were torch-related — nothing to install."
        rm -f "$tmp"
        return 0
    fi

    pip install --no-cache-dir -r "$tmp"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# Install the requirements of a tool's custom nodes / extensions.
#
# Separate from rocm_ai_install_deps on purpose, because it must be called from
# *both* paths that touch an environment: installing or updating a tool, and
# rebuilding the environment during an upgrade. The upgrade previously called only
# rocm_ai_install_deps, which handles the top-level requirements file and nothing
# else — so after a rebuild every custom node's dependencies were left
# uninstalled. A machine with 19 nodes was missing 48 packages and nothing said so.
#
# Failures are reported instead of swallowed. A silently missing dependency
# surfaces much later as a confusing ImportError in the middle of a workflow.
rocm_ai_install_extension_deps() {
    local key="$1" dir
    dir="$(rocm_ai_tool_dir "$key" 2>/dev/null)"
    [ -d "$dir" ] || return 0

    local -a subdirs=()
    local s
    for s in "$dir/custom_nodes" "$dir/extensions"; do
        [ -d "$s" ] && subdirs+=("$s")
    done
    [ "${#subdirs[@]}" -eq 0 ] && return 0

    local checked=0 installed=0 failed=0 node name req log
    for s in "${subdirs[@]}"; do
        for node in "$s"/*/; do
            [ -d "$node" ] || continue
            name="$(basename "$node")"

            # Keep the node itself current when it is a git checkout.
            if [ -d "$node/.git" ]; then
                git -C "$node" pull --ff-only >/dev/null 2>&1 || true
            fi

            for req in requirements.txt requirements_linux.txt; do
                [ -f "$node/$req" ] || continue
                checked=$((checked + 1))
                # Capture output so a failure can be shown, while a successful
                # install stays quiet.
                log="$(mktemp /tmp/rocm-node-req.XXXXXX)"
                if rocm_ai_pip_filtered "$node/$req" >"$log" 2>&1; then
                    installed=$((installed + 1))
                else
                    failed=$((failed + 1))
                    ai_warn "    $name: some packages from $req did not install"
                    grep -iE 'error' "$log" 2>/dev/null | head -3 | while IFS= read -r l; do
                        printf '        %s\n' "$l"
                    done
                fi
                rm -f "$log"
            done
        done
    done

    if [ "$checked" -gt 0 ]; then
        if [ "$failed" -eq 0 ]; then
            ai_dim "  $installed extension requirement file(s) satisfied"
        else
            ai_warn "  $installed of $checked extension requirement file(s) installed; $failed had errors"
            ai_dim  "  Retry one node with:  pip install -r <node>/requirements.txt"
        fi
    fi
    return 0
}

# --- Update -------------------------------------------------------------------

rocm_ai_update_tool() {
    local key="$1" name dir venv
    name="$(rocm_ai_tool_name "$key")" || return 1
    dir="$(rocm_ai_tool_dir "$key")"
    venv="$(rocm_ai_tool_venv "$key")"

    if [ ! -d "$dir/.git" ]; then
        ai_warn "$name is not a git checkout — cannot update."
        return 1
    fi

    ai_banner "Updating $name"
    ai_require_venv "$venv" || return 1

    git -C "$dir" pull --rebase --autostash || ai_warn "git pull had issues — continuing"
    if [ -f "$dir/.gitmodules" ]; then
        git -C "$dir" submodule update --init --recursive || ai_warn "submodule update had issues"
    fi
    rocm_ai_install_deps "$key"
    rocm_ai_install_extension_deps "$key"

    ai_ok "$name updated."
    return 0
}

# --- Shortcuts ----------------------------------------------------------------

# Create a double-clickable .bat on the Windows desktop. Uses `wsl.exe -- bash -l`
# with the script path as a positional argument; the older
# `wsl.exe %s ~ -e bash -ic` form was malformed and produced windows that closed
# instantly.
rocm_ai_create_shortcut() {
    local key="$1"
    local name dir script port

    name="$(rocm_ai_tool_name "$key")" || { ai_err "Unknown tool '$key'"; return 1; }
    dir="$(rocm_ai_tool_dir "$key")"
    port="$(rocm_ai_tool_effective_port "$key")"

    if ! ai_is_wsl; then
        ai_err "Desktop shortcuts require WSL2 (they are Windows files)."
        return 1
    fi
    if ! command -v cmd.exe >/dev/null 2>&1; then
        ai_err "Cannot reach cmd.exe — Windows interop appears to be disabled."
        return 1
    fi

    script="$TOOLKIT_ROOT/scripts/start/$(rocm_ai_start_script_for "$key")"
    if [ ! -f "$script" ]; then
        ai_err "Start script missing: $script"
        return 1
    fi

    local win_profile desktop
    win_profile="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r\n')"
    [ -z "$win_profile" ] && { ai_err "Could not determine the Windows user profile."; return 1; }
    desktop="$(wslpath "$win_profile/Desktop" 2>/dev/null)"
    [ -d "$desktop" ] || { ai_err "Windows Desktop folder not found at $desktop"; return 1; }

    local distro_arg=""
    [ -n "${WSL_DISTRO_NAME:-}" ] && distro_arg="-d \"$WSL_DISTRO_NAME\""

    local bat="$desktop/${name// /_}.bat"
    {
        printf '@echo off\r\n'
        printf 'title %s  -  ROCm AI Toolkit\r\n' "$name"
        printf 'echo.\r\n'
        printf 'echo  ==========================================\r\n'
        printf 'echo   %s  -  ROCm AI Toolkit\r\n' "$name"
        printf 'echo  ==========================================\r\n'
        printf 'echo   Starting WSL. First launch takes a moment.\r\n'
        if [ "$port" != "-" ]; then
            printf 'echo   When you see "Running on", open:  http://localhost:%s\r\n' "$port"
        fi
        printf 'echo   Close this window to stop the server and free VRAM.\r\n'
        printf 'echo  ==========================================\r\n'
        printf 'echo.\r\n'
        printf 'wsl.exe %s -- bash -l "%s"\r\n' "$distro_arg" "$script"
        printf 'echo.\r\n'
        printf 'echo  Server stopped.\r\n'
        printf 'pause\r\n'
    } > "$bat"

    # Verify it actually has CRLF endings — a LF-only .bat misbehaves on Windows.
    if ! grep -q $'\r' "$bat" 2>/dev/null; then
        ai_warn "Shortcut written but line endings look wrong. Recreating with CRLF."
        sed -i 's/$/\r/' "$bat"
    fi

    ai_ok "Desktop shortcut created: ${name// /_}.bat"
    return 0
}

# Map a tool key to its start script filename.
rocm_ai_start_script_for() {
    case "$1" in
        comfyui)       printf 'comfyui.sh' ;;
        sdnext)        printf 'sdnext.sh' ;;
        automatic1111) printf 'automatic1111.sh' ;;
        kohya_ss)      printf 'kohya_ss.sh' ;;
        textgen)       printf 'textgen.sh' ;;
        *)             printf 'custom.sh' ;;
    esac
}

# --- Launch -------------------------------------------------------------------

# Launch any registry tool, including user-registered third-party ones, through
# the shared launch layer so they get the GPU environment and tuned profile.
rocm_ai_launch_tool() {
    local key="$1"; shift || true
    local name dir entry port venv kind

    name="$(rocm_ai_tool_name "$key")" || { ai_err "Unknown tool '$key'"; return 1; }
    dir="$(rocm_ai_tool_dir "$key")"
    venv="$(rocm_ai_tool_venv "$key")"
    kind="$(rocm_ai_registry_field "$key" kind)"
    port="$(rocm_ai_tool_effective_port "$key")"

    if ! rocm_ai_tool_installed "$key"; then
        ai_err "$name is not installed."
        ai_say "     Install it:  ./menu.sh  ->  Install  ->  $name"
        return 1
    fi

    # Built-in tools each have a bespoke start script that knows their own
    # correct arguments (SD.Next needs --use-rocm, kohya needs a GUI entry point,
    # and so on).
    local script="$TOOLKIT_ROOT/scripts/start/$(rocm_ai_start_script_for "$key")"
    if [ "$kind" != "custom" ] && [ -f "$script" ]; then
        bash "$script" "$@"
        return $?
    fi

    # User-registered tools run whatever command they were configured with.
    entry="$(rocm_ai_registry_field "$key" entry)"
    ai_launch --name "$name" --dir "$dir" --command "$entry" --venv "$venv" \
              --port "$port" --tool-key "$key" --allow-extra-args -- "$@"
}
