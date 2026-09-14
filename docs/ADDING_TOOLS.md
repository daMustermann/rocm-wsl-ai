# Adding your own tools

The toolkit can install, launch, update and create Windows desktop shortcuts for
**any** Git repository — it does not have to be one of the built-in five.

This is also how you run third-party applications that the toolkit deliberately
does not list itself. See [the policy note](#a-note-on-what-is-not-in-the-registry)
at the end.

There are two ways: the interactive menu, and editing the registry directly.

---

## Option 1 — from the menu (recommended)

**Install → Add a third-party tool**

You will be asked for:

| Prompt | Example | Notes |
|---|---|---|
| Display name | `My Tool` | Shown in the menu and used for the shortcut name |
| Git repository URL | `https://codeberg.org/user/my-tool.git` | Any host. `owner/repo` is expanded to a GitHub URL |
| Install directory | `~/my-tool` | Defaults to `~/<repo-name>` |
| Command to run | `python app.py --listen` | Run from inside the install directory |
| Web port | `7860` | Blank for CLI-only tools |
| Python environment | `genai_env` | The shared inference environment, or `kohya_env` |

The entry is stored in `~/.config/rocm-wsl-ai/tools.local` and becomes a normal
tool everywhere: it appears in **Launch**, in **Updates**, and can be put on your
Windows desktop.

---

## Option 2 — edit the registry

Registry entries are pipe-separated lines. Built-ins live in
[`lib/tools.sh`](../lib/tools.sh); your own go in `~/.config/rocm-wsl-ai/tools.local`.

```text
key|Display Name|repo-url|install-dir|venv|launch-entry|port|kind|notes
```

| Field | Meaning |
|---|---|
| `key` | Stable identifier used in config and shortcut names. Lowercase, no spaces. |
| `Display Name` | What the menu shows. |
| `repo-url` | Git remote, or `-` for something that is not a clone. |
| `install-dir` | Absolute path. `$HOME` is expanded. |
| `venv` | `genai_env` (shared inference), `kohya_env` (training), or `own` → treated as `genai_env`. |
| `launch-entry` | Path relative to `install-dir` that must exist for the tool to count as installed. For third-party entries this is the **command** to run instead. |
| `port` | Default web port, or `-` for CLI-only. |
| `kind` | `comfyui` · `webui` · `gradio` · `cli` · `custom`. |
| `notes` | One-line description shown in the menu. |

Example:

```text
mytool|My Tool|https://codeberg.org/user/my-tool.git|$HOME/my-tool|genai_env|python app.py --listen|7860|custom|A tool I use
```

Then install it from **Install → My Tool**.

### Why no Windows path?

Everything runs inside WSL. Use the Linux view of your files, for example
`/mnt/c/Users/you/tools/mytool` rather than `C:\Users\you\tools\mytool`.

---

## Writing a proper start script

Registering a repository is enough to get it running, but a dedicated start script
gives you better behaviour: GPU preflight, the tuned profile, hibernation, and a
helpful error instead of a stack trace.

Create `scripts/start/mytool.sh`:

```bash
#!/bin/bash
set -uo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export TOOLKIT_ROOT
. "$TOOLKIT_ROOT/lib/launch.sh"

ai_load_env >/dev/null 2>&1 || true

MYTOOL_DIR="${MYTOOL_DIR:-$HOME/my-tool}"
PORT="${MYTOOL_PORT:-7860}"

ai_launch \
    --name "My Tool" \
    --dir "$MYTOOL_DIR" \
    --command "python app.py --listen --port $PORT" \
    --venv "genai_env" \
    --port "$PORT" \
    --allow-extra-args \
    -- "$@"
```

Then make it executable and add it to the registry's `kind` as `custom`, setting
`launch-entry` to a file that must exist:

```bash
chmod +x scripts/start/mytool.sh
```

### What `ai_launch` does for you

| Flag | Effect |
|---|---|
| `--name` | Label in output and errors |
| `--dir` | Working directory; checked for existence up front |
| `--command` | Command line to run inside `--dir` |
| `--venv` | Python environment to activate first |
| `--port` | Used for the printed URL, the wake server, and status detection |
| `--tool-key` | `comfyui` opts into tuned ComfyUI flag injection |
| `--allow-extra-args` | Forward arguments passed to your script |
| `--no-hibernate` | Skip idle hibernation |
| `--preflight-force` | Re-check the GPU immediately instead of using the cache |

You get, automatically:

- The full GPU environment (`HSA_ENABLE_DXG_DETECTION`, MIOpen cache paths, the
  `PYTORCH_HIP_ALLOC_CONF` guard) set **before** Python starts.
- Your tuned performance profile applied.
- A cached GPU preflight with the five-step fix checklist if the GPU is missing.
- Idle hibernation that returns VRAM to Windows, with a browser wake page.
- A clear error if the port is already in use.

### Special-casing a tool

If your tool needs arguments the toolkit does not know about, use the environment
hook rather than editing the launcher:

```bash
# ~/.config/rocm-wsl-ai/user.env
export MYTOOL_EXTRA_ARGS="--precision fp16 --enable-feature-x"
```

…and reference `${MYTOOL_EXTRA_ARGS:-}` in your command string.

---

## Adding to the built-in registry

If your tool is broadly useful and openly hosted, a pull request adding it to
`ROCM_AI_TOOL_REGISTRY` in `lib/tools.sh` is welcome. Please include:

- A `git clone` URL that works without authentication.
- Verification that the tool actually runs on ROCm 7.2.3 / `gfx1100` or newer.
- A start script if the tool needs anything beyond a bare command.
- A note in `CHANGELOG.md`.

---

## A note on what is not in the registry

The built-in registry lists only tools that are openly hosted and broadly
distributed. It deliberately does **not** list face-swap or
likeness-manipulation applications.

That is an editorial decision, not a technical limitation. The generic mechanism
above installs and runs such tools perfectly well, from any host, under a name of
your choosing.

The reason for the split:

- GitHub's Acceptable Use Policies prohibit non-consensual intimate imagery and
  synthetic or manipulated media intended to mislead. This is why most face-swap
  repositories were removed from GitHub.
- A project that ships an installer for a named face-swap application tends to be
  reported and taken down, whether or not the tool itself is lawful.
- The registry is generic precisely so the toolkit can stay useful and stay
  available.

If you register such a tool yourself, you are responsible for complying with its
licence, the laws where you live, and — most importantly — the consent of the
people in any images you process. Non-consensual intimate imagery is illegal in
many jurisdictions and causes real harm.

`~/.config/rocm-wsl-ai/tools.local` is never committed to this repository, and
`.gitignore` excludes it.

---

## Removing a tool

Delete its line from `~/.config/rocm-wsl-ai/tools.local` (or the install directory
itself for `rocm_ai_tool_installed` to stop detecting it). The toolkit never
deletes your files for you.

Built-in tools are removed the same way: delete the install directory, and it stops
appearing in the menu.
