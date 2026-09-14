# Changelog

All notable changes to this project will be documented in this file.

## [4.1.0] - 2026-09-14

Upgrades are now a single command, ROCm versions are discovered rather than
pinned, and settings left behind by older versions are repaired automatically.

### ⬆️ One-command upgrade (`./upgrade.sh`)

- **New `upgrade.sh`** brings any older installation fully up to date in ten
  ordered stages: detect, report, toolkit, migrate, shell environment, ROCm,
  ROCDXG, Python environment, tools, retune, verify. Stages that are already
  done are skipped, so it is safe to re-run after a failure.
- **`--check`** reports what would change and touches nothing. Also surfaced in
  the menu, which now shows a one-line upgrade summary, and on the home screen,
  where an available ROCm upgrade outranks tuning in the "next step" hint.
- **`install.sh` detects an existing installation** and routes to `upgrade.sh`
  instead of treating the user as a first-time setup.
- Every stage is logged to `~/.config/rocm-wsl-ai/logs/upgrade-<timestamp>.log`.

### 🔄 ROCm versions are discovered, not pinned

- **Removed every hardcoded version.** The installer previously pinned wheel
  filenames such as `torch-2.9.1+rocm7.2.3.lw.gitebc02d69-cp310-cp310-linux_x86_64.whl`.
  Those embed a git hash that changes with every ROCm patch release, so each new
  AMD release broke the installer until someone edited the script.
- **New `lib/version.sh`** queries AMD's repository index at run time and picks
  the newest release that has both an apt repository for your Ubuntu version and
  PyTorch wheels for your Python version. The two are checked separately, so a
  ROCm release published before its wheels cannot be selected.
- **`librocdxg` is resolved from GitHub release tags** rather than the default
  branch.
- **Results are cached for 24 hours** and every resolver has an offline
  fallback, so an unreachable network degrades to a known-good version instead
  of failing.
- Practical effect: **new ROCm releases work without a toolkit update.**
  `./upgrade.sh --check` offers them as soon as AMD publishes them.

### 🩹 Automatic configuration migration (`lib/migrate.sh`)

Upgrading the code is only half an upgrade; 3.x-era configuration would have
quietly undone the 4.x fixes. Six migrations run automatically, each idempotent,
each backing the file up first, and each reported in plain language:

- **`PYTORCH_HIP_ALLOC_CONF`** is disabled wherever it appears — the venv
  `activate` scripts, `.bashrc`, `.profile` and `user.env`. Older versions wrote
  it deliberately, and it **segfaults** PyTorch 2.9.1+rocm7.2.3 on import.
- **`~/.genai_opt_profile`** is retired; its `MIGRAPHX_MLIR_USE_SPECIFIC_OPS` and
  `PYTORCH_ALLOC_CONF` values had no effect on PyTorch's HIP backend.
- **A stale `HSA_OVERRIDE_GFX_VERSION` in `gpu.env` is removed** — with ROCDXG
  installed it makes the runtime reject the device, hiding the GPU entirely.
- **Stale caches** (`.preflight`, `.gpu_summary`, `.engine_summary`) are cleared
  so hardware is re-detected with the corrected configuration.
- **`user.env` gains** the settings introduced in 4.x.
- **Broken desktop shortcuts** from before 3.3.0 are renamed, not deleted.

### 🔌 GPU environment for every shell

- **New login-shell integration.** `HSA_ENABLE_DXG_DETECTION` must be set before
  Python starts; without it libhsa reports zero GPU agents and `torch` sees no
  device, while `rocminfo` still lists the GPU. Version 3.x wrote it into the
  virtualenv's `activate` script, so the GPU existed *only* inside an activated
  venv — invisible to an IDE, a Jupyter kernel, a cron job, or a plain `python3`.
- The installer and upgrade now write `/etc/profile.d/rocm-wsl-ai.sh` (falling
  back to `~/.bashrc`), so the GPU works from any terminal.
- The installer **no longer persists `HSA_OVERRIDE_GFX_VERSION` into the venv**,
  which was the exact mechanism that hid GPUs.

### 🏗️ Installer

- **Replaced the `amdgpu-install` .deb path with AMD's signed apt repository.**
  The old approach needed a package build number (`7.2.3.70203-1`) that changes
  independently of the ROCm version and broke whenever AMD republished. Adding
  the repository and installing the `rocm` metapackage is what AMD's own
  quick-start recommends and lets apt produce real upgrade paths.
- An existing apt source is **amended rather than duplicated**, so apt cannot end
  up with two competing ROCm repositories.

### 📚 Documentation

- **New [`docs/UPGRADING.md`](docs/UPGRADING.md)** — the upgrade guide, with a
  what-gets-migrated table, per-version notes for users coming from 3.0.x through
  4.0.0, troubleshooting, and an explanation of why versions are no longer
  pinned.
- README opens with a prominent upgrade notice, and the version table now reads
  "resolved at run time" rather than naming a version.
- `docs/TROUBLESHOOTING.md` gained an upgrade section.

---

## [4.0.0] - 2026-09-14

A rewrite of the performance, launch and usability layers, driven by measurement
on real hardware rather than assumption. Several earlier "optimisations" turned out
to do nothing, and one turned out to be actively harmful.

### 🚀 Performance — measured, not guessed

- **New performance engine** (`scripts/utils/perf_engine.py`). Replaces the old
  auto-tuner with a real measurement harness:
  - `probe` — reports what the machine actually supports (GPU arch, dtypes, usable
    attention kernels, optional packages).
  - `bench` — builds candidates, measures each in its own subprocess, ranks them,
    and applies the winner.
  - `apply` / `show` — persist and display the active profile.
  - `doctor` — self-check that works without a GPU, including a PyTorch boot test
    under a real profile environment.
- **The old auto-tuner was measuring nothing.** It benchmarked 4096×4096 fp32
  `matmul` + `softmax` and attributed the noise to `MIGRAPHX_MLIR_USE_SPECIFIC_OPS`
  and `PYTORCH_ALLOC_CONF`. MIGRAPHX is a separate runtime that PyTorch does not use
  unless `torch_migraphx` is installed, and the allocator variable has no effect on
  this workload, so the "winner" was statistically meaningless. Both were removed.
- **`PYTORCH_HIP_ALLOC_CONF` causes a segfault** on torch 2.9.1+rocm7.2.3 and is no
  longer set anywhere. Isolated on gfx1100: `PYTORCH_ALLOC_CONF` is fine,
  `PYTORCH_HIP_ALLOC_CONF` exits with SIGSEGV (-11) before torch finishes importing.
  An earlier version of this toolkit migrated users *towards* this variable. The
  launcher now strips it, warns about it, and `doctor` fails if a profile ever emits
  it again.
- **MIOpen convolution cache is now persisted for every tool.** Measured first
  convolution on an RX 7900 XTX: `FIND_MODE=NORMAL` **2219 ms** vs `FIND_MODE=FAST`
  **845 ms**, reproducible in both candidate orders. This is the largest single win
  in the release and it applies to every launch, not just tuned ones.
- **Stopped forcing `--lowvram --disable-pinned-memory` on every GPU.** That forced
  `VRAMState.LOW_VRAM`, where ComfyUI splits the model into per-block chunks loaded
  and freed around each sampling step. On a 24 GB card it was pure loss. VRAM flags
  are now derived from measurement.
- **ComfyUI flags are validated before use.** The installed `main.py --help` is read
  and unsupported flags are dropped, so a flag from a newer release cannot make an
  older checkout exit on launch.
- **Numerically wrong configurations cannot win.** Fused attention kernels are
  compared against an eager reference; deviations over 2% relative L2 are rejected.
- **Noise is rejected, and ties are broken safely.** Candidates with a spread above
  20% of their median are discarded. Wins under 3% are reported as inconclusive and
  nothing is applied. Candidates within 4% are a tie, and the least aggressive VRAM
  mode wins — previously an OOM-prone profile could win a 2% "victory".
- **Three measurement traps are actively defended against**, each found by the
  engine disagreeing with a hand measurement:
  - *Wrong dtype.* `"auto"` precision fell through the worker's dtype chain to
    **fp32**. That made the fused attention kernels read 15.7 ms instead of 2.9 ms
    and declared the slowest kernel (`MATH`) the fastest — a 5x error that looked
    exactly like a real kernel difference. `"auto"` now resolves to bf16 with a
    verified fp16 fallback.
  - *GPU cold state.* The first denoise loop of a session measures **104 ms per
    step**, while every later run of the same configuration measures ~16 ms. The
    sweep now begins with a warm-up pass whose result is discarded.
  - *Drift across the sweep.* A long run can drift by more than 40%, which silently
    invalidates every comparison against the baseline. A reference configuration is
    now measured both before and after; a difference over 25% **discards the whole
    run** instead of reporting a result that cannot be trusted.
- **Attention no longer contributes to scoring.** No profile changes the attention
  kernel, and attention measured inside a long benchmark process inflates badly. It
  is measured once in a dedicated clean process and reported as information.
- Reference output on an RX 7900 XTX: **cold start 2213 ms → 955 ms**, denoise step
  **17.0 ms → 9.0 ms**, a ~55% improvement, with a measured 5% run drift.

### ⚡ Launch speed and correctness

- **Fixed the GPU-visibility trap.** `HSA_ENABLE_DXG_DETECTION` must be set before
  the Python process starts or `torch.cuda.is_available()` silently returns `False`
  — while `rocminfo` still lists the GPU. This was previously appended to the
  virtualenv's `activate` script, so the GPU disappeared in a fresh shell, from an
  IDE, or from any script that did not activate that venv. `lib/launch.sh` now
  exports the full GPU environment first, in every launch path.
- **Launch overhead reduced from ~2.5 s to ~4 ms** on the warm path. The preflight
  result is cached against torch version, Windows driver version and ROCDXG
  presence, with a 15-minute trust window; it is never cached when it failed.
- **New `lib/launch.sh`** replaces ~150 lines of duplicated environment setup in the
  start scripts with a single `ai_launch` entry point.
- **`lib/common.sh` no longer does work at source time.** It previously ran GPU
  auto-detection — shelling out to `rocminfo` and PowerShell — on every `source`,
  adding seconds to startup and writing files as a side effect of importing a
  library. All detectable startup side effects were removed.
- **Idle hibernation no longer spawns two extra Python interpreters.** Roughly 40
  lines of bash replace `smart_sleep_wrapper.py` + `wake_server.py` (~150 MB of
  resident Python). `SIGINT` is still forwarded so Ctrl+C behaves as before.
- **Base environments are no longer destroyed by re-entry.** `scripts/install/kohya_ss.sh`
  ran `python3 -m venv` unconditionally, which regenerates the scripts directory of
  an existing environment and can leave it half-broken; it now reuses an existing
  venv and mirrors the ROCm PyTorch build from `~/genai_env`.

### 🎨 Usability

- **New home screen** that reports GPU, engine status, tuning state and live tool
  status, then computes the single most useful **next step** from the machine's
  actual state instead of presenting a wall of options.
- **New "Quick start"** that walks a new user through base install → WSL restart →
  first tool → tuning in order.
- **Stop all AI servers and free VRAM** — one action to reclaim VRAM from every
  tool the toolkit knows about, escalating to `SIGKILL` if a process refuses to stop.
- **Menus can no longer dead-end.** A cancelled or unknown selection returns to the
  previous menu; previously an Esc or unknown choice was a silent no-op.
- **`gum` is now optional.** Every screen has a plain-text fallback, and asking to
  install `gum` no longer exits if the install fails.
- **Errors name the fix.** Failure messages include the exact menu path or command
  that resolves them.
- **Version is a single source of truth** (`VERSION`), replacing four hardcoded
  copies that had already drifted apart.

### 🧰 Tools

- **New `lib/tools.sh` registry.** Install, update, launch and shortcut creation are
  now driven by one table, so adding a tool is a one-line change. Adds Text
  Generation WebUI as a launchable tool.
- **Register any Git repository as a first-class tool** from the menu, or in
  `~/.config/rocm-wsl-ai/tools.local`. Any host is supported; the entry gets
  cloning, dependency installation, launching, updating and a desktop shortcut.
- The built-in registry lists only openly hosted tools. Face-swap and
  likeness-manipulation applications are deliberately not listed — GitHub's
  Acceptable Use Policies prohibit non-consensual intimate imagery and synthetic
  media intended to mislead, and repositories shipping installers for named
  face-swap apps are routinely removed. The generic registry exists so users can
  register any tool themselves without putting the project in that position. See
  [`docs/ADDING_TOOLS.md`](docs/ADDING_TOOLS.md).

### 📚 Documentation

- Rewritten `README.md`: what the toolkit does, real measured numbers with the
  methodology behind them, the GPU-visibility trap explained, and a troubleshooting
  index.
- New [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) — every lever, what was measured,
  and the folklore that was removed.
- New [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — symptom-first fixes.
- New [`docs/ADDING_TOOLS.md`](docs/ADDING_TOOLS.md) and
  [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
- New `install.sh` one-line installer, `LICENSE`, `.gitignore`, CI workflow, issue
  and PR templates, `CONTRIBUTING.md` and `SECURITY.md`.

### 🔧 Fixed

- Base install no longer emits `PYTORCH_HIP_ALLOC_CONF` into the venv activation
  script.
- Settings menu no longer writes empty `export VAR=""` lines, which hide every GPU
  from ROCm.
- `create_shortcut.sh` verifies it produced CRLF line endings, and supports both the
  registry form and the older two-argument form.
- `gpu_diag.sh` distinguishes "ROCm not installed" from "installed but no GPU
  found", instead of reporting the latter as the former.

### ⚠️ Breaking changes

- `~/.genai_opt_profile` is no longer read. Tuning lives in
  `~/.config/rocm-wsl-ai/perf.env` and `perf_profile.json`, written only by
  `perf_engine.py`. Run **Performance → Auto-tune** once after upgrading.
- The old `MIGRAPHX_MLIR_USE_SPECIFIC_OPS` and `PYTORCH_ALLOC_CONF` exports are gone
  from the launch path. Remove any copies you added by hand to `user.env`.
- `lib/common.sh` no longer performs GPU detection at source time. Scripts that
  relied on that side effect should call `ai_load_env` from `lib/launch.sh`.

---

## [3.4.0] - 2026-06-11

### 🔧 Bugfixes · 🤖 Smart Update

#### ✨ Added
- **Smart Update** (`scripts/utils/smart_update.sh`):
  - Scans every installed component automatically and shows a colour-coded status table
  - ROCm: compares `/opt/rocm/.info/version` against target 7.2.3
  - ROCDXG: checks for `/opt/rocm/lib/librocdxg.so`
  - PyTorch: activates `genai_env` in a sub-shell, reads `torch.__version__` and compares against target 2.9.1
  - ComfyUI / SD.Next / Automatic1111 / kohya_ss / TextGen WebUI: `git fetch` + `rev-list HEAD..origin/<branch> --count` (shows exact number of commits behind)
  - Ollama: compares installed version against GitHub releases API (5 s timeout, non-fatal)
  - Three modes: **Update all** (one keystroke) · **Pick** (gum multi-select or numbered plain-text) · **Cancel**
  - Optional re-scan after update run to verify everything is now up to date
  - Borrows existing `update_*` functions from `update_ai_setup.sh` via source-guard — no duplication
- **`update_ai_setup.sh`**: New menu entry `s. 🤖 Smart Update` at the top of both gum and text menus

#### 🐛 Fixed
- **`update_ai_setup.sh`**: Added missing `update_rocm` function — running "Update ROCm stack" previously crashed with `command not found` on line 302
- **`update_ai_setup.sh`**: Removed dead duplicate `update_pytorch` definition (old nightly variant) — second definition silently overwrote the first; only the ROCm 7.2.3 variant is now active
- **`update_ai_setup.sh`**: Added source-guard at bottom so the script can be sourced by `smart_update.sh` without launching its interactive menu
- **`scripts/install/automatic1111.sh`**: `TORCH_COMMAND` corrected from `torch==2.8.0` → `torch==2.9.1` to match the toolkit target version
- **`scripts/install/automatic1111.sh`**: `SCRIPT_DIR` changed from relative `$(dirname "$0")` to absolute `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` — prevents broken paths when called from a different working directory
- **`scripts/install/comfyui.sh`**: Same `SCRIPT_DIR` fix as above
- **`scripts/install/sdnext.sh`**: Same `SCRIPT_DIR` fix as above
- **`scripts/install/sdnext.sh`**: PyTorch verification block no longer calls `exit(1)` when ROCm is not yet present — prints a warning and continues installation instead of aborting
- **`scripts/install/sdnext.sh`**: Removed redundant second venv activation (`ensure_venv` was called after the venv was already manually activated)

---

## [3.3.1] - 2026-06-02

### 🐛 Bugfix

#### 🔄 Changed
- **`scripts/utils/auto_tuner.sh`**: Replaced deprecated `PYTORCH_HIP_ALLOC_CONF` with `PYTORCH_ALLOC_CONF` in benchmark profiles `2_VRAM_Caching` and `3_Extreme_Tuning` — fixes the deprecation warning shown on PyTorch shutdown.

---

## [3.3.0] - 2026-05-28

### ⚙️ First-Run Wizard · GPU Diagnostics · GPU Profiles · Settings · Changenotes

#### ✨ Added
- **First-Run Welcome Wizard** (`scripts/utils/first_run.sh`):
  - Detects the very first launch of the toolkit (marker: `~/.config/rocm-wsl-ai/.first_run_done`)
  - Shows a full-screen gum welcome screen with a 4-step Quick Start guide
  - Automatically creates `~/.config/rocm-wsl-ai/user.env` with defaults on first run
  - Text fallback for systems without gum
- **GPU Diagnostics** (`scripts/utils/gpu_diag.sh`):
  - Comprehensive health check: WSL2 env, ROCm version, ROCDXG, HSA env vars, GPU agents via rocminfo, PyTorch CUDA availability, genai_env & kohya_env venvs, user.env, Windows AMD driver (via PowerShell)
  - Colour-coded status rows: ✔ ok (green) / ⚠ warn (orange) / ✖ fail (red) / ℹ info (blue)
  - Runs standalone (`bash scripts/utils/gpu_diag.sh`) or via Settings → GPU Diagnostics
- **Settings Menu** (`menu.sh` → `show_settings_menu()`):
  - New main-menu item "7. ⚙️ Settings" — Help moved to 8
  - Sub-menu: GPU Profile · Edit Settings · GPU Diagnostics
- **GPU Profile Selector** (`menu.sh` → `show_gpu_profile_menu()`):
  - Parses `rocminfo` output to list all detected AMD GPU agents with marketing name and gfx arch
  - Choose "Auto" (clears overrides), a specific GPU (sets `ROCR_VISIBLE_DEVICES` + `HSA_OVERRIDE_GFX_VERSION`), or enter a manual gfx string
  - Writes selection persistently to `~/.config/rocm-wsl-ai/user.env`
- **Settings Editor** (`menu.sh` → `show_settings_editor()`):
  - Edit all user.env keys via `gum input` with current values pre-filled
  - Keys: `HSA_OVERRIDE_GFX_VERSION`, `ROCR_VISIBLE_DEVICES`, `HSA_ENABLE_DXG_DETECTION`, `COMFYUI_PORT`, `SDNEXT_PORT`, `A1111_PORT`, `KOHYA_PORT`
  - Option to open `user.env` raw in `$EDITOR` / nano / vi
- **Changenotes on Self-Update** (`menu.sh` → `_show_update_changenotes()`):
  - After a successful `git pull`, extracts the top section of `CHANGELOG.md` and displays it in `gum pager --soft-wrap`
- **Persistent User Settings** (`lib/common.sh` — `ensure_user_env`, `load_user_env`, `_update_user_env`):
  - `ensure_user_env` creates `~/.config/rocm-wsl-ai/user.env` with a well-documented template on first use
  - `load_user_env` sources user.env; called at menu.sh startup and from all launch scripts
  - `_update_user_env KEY VALUE` safely updates a single key in user.env (sed in-place)
  - All three functions exported via `export -f` for use in subshells / sourced scripts

#### 🔄 Changed
- `menu.sh`: Sources `first_run.sh` and `gpu_diag.sh` at startup; calls `ensure_user_env && load_user_env` before any menu is shown; calls `first_run_check` before SDK/upgrade checks
- `scripts/start/comfyui.sh`: Sources `user.env`; port defaults to `${COMFYUI_PORT:-8188}`
- `scripts/start/sdnext.sh`: Sources `user.env`; port defaults to `${SDNEXT_PORT:-7860}` via `--port` arg
- `scripts/start/automatic1111.sh`: Sources `user.env`; port defaults to `${A1111_PORT:-7860}` via `--port` arg
- `scripts/start/kohya_ss.sh`: Sources `user.env` via `load_user_env`; port defaults to `${KOHYA_PORT:-7861}`

---

## [3.2.0] - 2026-05-28

### 🎨 kohya_ss Model Training + Self-Update + Shortcut Fix

#### ✨ Added
- **kohya_ss integration** (`scripts/install/kohya_ss.sh`, `scripts/start/kohya_ss.sh`):
  - Install [kohya_ss](https://github.com/bmaltais/kohya_ss) for LoRA, DreamBooth, and fine-tuning directly on your AMD GPU
  - Uses a dedicated `~/kohya_env` virtual environment to avoid dependency conflicts with inference tools
  - Hugging Face Accelerate auto-configured for single-GPU ROCm (non-interactive)
  - GUI starts on `http://localhost:7861`
- **Self-Update** (`menu.sh` → Updates menu):
  - New **Updates** main menu entry (`🔄 Updates`)
  - **Check for Toolkit Updates**: runs `git fetch`, shows new commits, applies `git pull --rebase --autostash`
  - **Update Installed AI Tools**: launches the Update Manager (update_ai_setup.sh)
- **kohya_ss in Update Manager** (`update_ai_setup.sh`):
  - `update_kohya_ss()`: pulls latest code + reinstalls requirements in kohya_env
  - `self_update_toolkit()`: standalone self-update for when running update_ai_setup.sh directly
  - Gum-based UI for the Update Manager (text fallback when gum is unavailable)

#### 🐛 Fixed
- **Windows Desktop Shortcuts** (`scripts/utils/create_shortcut.sh`):
  - **Root cause**: generated `.bat` files used malformed `wsl.exe` syntax (`~ -e bash -ic "script"`) which caused the window to close immediately or the script never to run
  - **Fix**: corrected to `wsl.exe [-d Distro] -- bash -l "/path/to/script"` — `--` properly separates wsl.exe options from the Linux command; `bash -l` ensures a login shell with all environment variables loaded
  - Added title bar label and cleaner "Server stopped" exit message

#### 📝 Updated Menus
- **Install Tools**: added `kohya_ss (LoRA / Model Training)`
- **Launch Tool**: added `kohya_ss (Training GUI)`
- **Create Desktop Shortcuts**: added `kohya_ss`
- **System Status**: shows kohya_ss installation status
- **Help**: updated to list kohya_ss and self-update

#### 📚 Documentation
- `README.md`: new kohya_ss section, self-update section, Windows shortcut troubleshooting
- `docs/WSL2_SETUP_GUIDE.md`: new kohya_ss chapter, self-update chapter, Windows shortcuts chapter with troubleshooting table

---

## [3.1.0] - 2026-05-18

### 🔄 ROCm 7.2.3 Update

Bumps the entire stack to AMD's latest stable ROCm release (7.2.3, released May 4, 2026).

### ✨ Changed
- **ROCm 7.2.1 → 7.2.3**: Updated all installers and upgrade scripts to use the latest stable ROCm release
- **PyTorch wheels updated** to `+rocm7.2.3` (new git hash: `gitebc02d69`)
- **Wheel source URL** updated to `rocm-rel-7.2.3`
- **amdgpu-install package** updated to `7.2.3.70203-1`
- **Upgrade wizard** now migrates from ROCm 7.2.1 → 7.2.3
- Menu banner, help text, and all UI strings updated to v3.1.0
- `update_ai_setup.sh` header updated to reflect ROCm 7.2.3

### 🛠️ Technical Details
- amdgpu-install package: 7.2.3.70203-1
- PyTorch wheels: `torch-2.9.1+rocm7.2.3.lw.gitebc02d69`
- torchvision wheels: `torchvision-0.24.0+rocm7.2.3.gitb919bd0c`
- torchaudio wheels: `torchaudio-2.9.0+rocm7.2.3.gite3c6ee2b`
- Wheel source: `https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.3/`
- Triton version: 3.5.1+rocm7.2.3

### 🔗 References
- [ROCm 7.2.3 Release Notes](https://rocm.docs.amd.com/en/latest/release/versions.html)
- [AMD ROCm Radeon/Ryzen Docs](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/)

---

## [3.0.0] - 2026-03-27

### 🎉 Major Release - ROCDXG Architecture Upgrade

AMD has replaced the legacy `roc4wsl` WSL approach with the new open-source **ROCDXG (librocdxg)** library in ROCm 7.2.1. This release fully adopts the new architecture.

### ✨ Added
- **ROCDXG (librocdxg) Support**: The base installer now builds and installs librocdxg from source, enabling GPU compute via Microsoft's DXCore interface
- **Upgrade Migration Wizard**: New menu option (`Install Tools → Upgrade`) safely migrates from ROCm 7.2.0 to 7.2.1 while preserving all AI tools, models, and custom nodes
- **Startup Upgrade Detection**: TUI automatically detects old ROCm without ROCDXG and shows a clear upgrade notice with instructions
- **Windows SDK Auto-Detection**: Automatically locates the Windows SDK path required for building librocdxg
- **`HSA_ENABLE_DXG_DETECTION=1`**: New environment variable automatically set in venv activation, GPU config, and all launch scripts
- **`has_rocdxg()` Helper**: New function in `lib/common.sh` to check for librocdxg installation
- **Ryzen Strix / Strix Halo APU Support**: First officially supported Ryzen APUs for WSL AI workloads

### 🔄 Changed
- **BREAKING**: ROCm 7.2.0 → **7.2.1** — uses `apt install rocm` instead of `amdgpu-install --usecase=wsl,rocm`
- **BREAKING**: Windows driver requirement bumped from Adrenalin 26.1.1 to **26.2.2+**
- **BREAKING**: Windows SDK now required as a prerequisite for ROCDXG build
- PyTorch wheels updated to `+rocm7.2.1` (new git hashes: `gitff65f5bc`)
- Wheel source URL updated to `rocm-rel-7.2.1`
- `sageattention` is now bundled natively into the base python environment by default
- All launch scripts (`comfyui.sh`, `sdnext.sh`, `automatic1111.sh`) now export `HSA_ENABLE_DXG_DETECTION=1`
- `gpu_config.sh` now exports `HSA_ENABLE_DXG_DETECTION=1` and writes it to `gpu.env`
- `update_ai_setup.sh` updated to target ROCm 7.2.1 PyTorch index URL
- Menu banner and help text updated to v3.0.0

### 📚 Documentation
- README updated with ROCDXG architecture, Ryzen APU support, Windows SDK prerequisite
- Troubleshooting updated with ROCDXG-specific guidance
- Technical details table updated with new component versions

### 🛠️ Technical Details
- amdgpu-install package: 7.2.1.70201-1
- PyTorch wheels: `torch-2.9.1+rocm7.2.1.lw.gitff65f5bc`
- Wheel source: `https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/`
- Triton version: 3.5.1+rocm7.2.1

### ⚠️ Migration Notes
For users upgrading from 2.x:
1. **Reinstall required** — the installation method has changed fundamentally
2. Install **Adrenalin 26.2.2+** driver on Windows (replaces 26.1.1)
3. Install the **Windows SDK** on Windows (new requirement for librocdxg build)
4. Existing PyTorch environments will need to be recreated with new `+rocm7.2.1` wheels

### 🔗 References
- [AMD ROCDXG WSL Guide](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/howto_wsl.html)
- [librocdxg GitHub](https://github.com/ROCm/librocdxg/)
- [ROCm Quick Start](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/quick-start.html)
- [AMD Adrenalin 26.2.2 Release Notes](https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-WIN-26-2-2.html)

---

## [2.2.0] - 2026-03-23

### 🐛 Fixed
- **PyTorch Installer Bug**: Fixed a URL-encoding mismatch where files containing `%2B` were incorrectly decoded during `wget`, causing the official AMD PyTorch wheels to fail installation on strict pip environments.

---

## [2.1.0] - 2026-03-23

### 🎉 Major New Features
- **1-Click Windows Setup Wizard**: Added `Install_WSL_Ubuntu.bat`, a fully automated Windows script that completely bootstraps the WSL2 kernel and a clean Ubuntu 24.04 instance for absolute beginners with zero Linux knowledge.
- **💤 Smart Sleep VRAM Manager**: AI processes like ComfyUI now automatically enter hibernation mode after 30 minutes of inactivity to entirely free up GPU VRAM! Hitting port 8188 wakes it seamlessly back up via a proxy splash screen.
- **✨ Magic Settings Auto-Tuner**: New TUI dashboard option that actively runs PyTorch benchmark sweeps to perfectly optimize AMD arguments (`PYTORCH_HIP_ALLOC_CONF` and `MIGRAPHX`) for your specific GPU architecture.

### ✨ Added
- **Gorgeous TUI Upgrade**: Replaced standard whiptail menus with Charmbracelet `gum` for a highly styled, modern, and beautiful terminal interface.
- **Windows Desktop Shortcuts**: New menu option to automatically generate `wsl.exe` `.bat` shortcuts on the Windows Desktop for launching AI tools with one click.
- Automatic installation of `gum` dependency.

### 🔄 Changed
- Refactored `menu.sh` and `lib/common.sh` logging to use colored `gum style` blocks.
- Improved help and status readability.

---

## [2.0.0] - 2026-03-02

### 🎉 Major Release - Complete Overhaul

This release represents a complete overhaul of the ROCm WSL2 AI toolkit, focusing on the latest AMD stack and improved user experience.

### ✨ Added
- **ROCm 7.2.0** support (latest stable from AMD)
- **PyTorch 2.9.1** with official AMD wheels from repo.radeon.com
- **Ubuntu 24.04** as primary platform (Python 3.12)
- **New Simplified TUI** - Clean, modern menu system with emoji icons
- **Comprehensive WSL2 Setup Guide** (docs/WSL2_SETUP_GUIDE.md)
- Automatic Ubuntu version detection (noble/jammy)
- Automatic Python version selection (3.12/3.10)
- Official AMD `amdgpu-install` installation method
- WSL-specific runtime library fixes
- Enhanced status checking with detailed system information
- Quick help menu with essential information

### 🔄 Changed
- **BREAKING**: Now uses AMD's official `amdgpu-install` method instead of manual repository management
- **BREAKING**: Primary target is now Ubuntu 24.04 with Python 3.12 (22.04 still supported)
- **BREAKING**: Removed all deprecated `apt-key` usage
- Updated from PyTorch nightly index URLs to official AMD wheel downloads
- Simplified menu system - removed complex version selection
- Improved error messages with links to AMD documentation
- Better WSL2 detection and configuration
- Enhanced verification steps after installation

### 📚 Documentation
- Completely rewritten README.md with WSL2 focus
- New comprehensive WSL2_SETUP_GUIDE.md with troubleshooting
- Updated all version references to ROCm 7.2.0 and PyTorch 2.9.1
- Added quick start guide
- Added troubleshooting section
- Added performance tips for WSL2
- Updated links to AMD official documentation

### 🗑️ Removed
- Manual ROCm repository management (replaced with amdgpu-install)
- Deprecated apt-key commands
- Complex version selection menus
- Native Linux installation path (WSL2 focused)
- Outdated version detection from repo.radeon.com

### 🛠️ Technical Details
- Installation script: `scripts/install/setup_pytorch_rocm.sh`
- amdgpu-install package: 7.2.70200-1
- PyTorch wheels: cp312 (Ubuntu 24.04), cp310 (Ubuntu 22.04)
- Wheel source: https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/
- Triton version: 3.5.1+rocm7.2.0

### 📦 Wheel Downloads
**Ubuntu 24.04 (Python 3.12):**
- torch-2.9.1+rocm7.2.0
- torchvision-0.24.0+rocm7.2.0
- torchaudio-2.9.0+rocm7.2.0
- triton-3.5.1+rocm7.2.0

**Ubuntu 22.04 (Python 3.10):**
- torch-2.9.1+rocm7.2.0
- torchvision-0.24.0+rocm7.2.0
- torchaudio-2.9.0+rocm7.2.0
- triton-3.5.1+rocm7.2.0

### ⚠️ Migration Notes
For users upgrading from 1.x:

1. The installation method has changed - now uses AMD's official `amdgpu-install`
2. Existing installations may need to be reinstalled
3. Ubuntu 24.04 is now the recommended platform
4. PyTorch is now installed via official wheels, not nightlies

### 🔗 References
- [AMD ROCm WSL Installation Guide](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/install-radeon.html)
- [AMD PyTorch Installation Guide](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/native_linux/install-pytorch.html)
- [AMD Adrenalin 26.1.1 Release Notes](https://www.amd.com/en/resources/support-articles/release-notes/rn-rad-win-26-1-1.html)

---

## [1.0.0] - 2025-09-13

### Added
- Initial formal release entry (1.0.0)

### Changed
- ComfyUI installer now automatically clones and installs ComfyUI-Manager and ComfyUI-Lora-Manager
- Automatic1111 installer now clones/pulls latest repository and upgrades requirements
- SD.Next installer now clones/pulls latest repository and upgrades requirements
- ROCm / PyTorch install flows hardened for RDNA3+ hardware (gfx11xx/gfx12xx)

### Removed
- Support for InvokeAI, Fooocus, and SD WebUI Forge to reduce maintenance surface

### Documentation
- README.md updated to reflect supported tools

### Notes
- Baseline version numbering as 1.0.0



