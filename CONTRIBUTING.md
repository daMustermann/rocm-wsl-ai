# Contributing to the ROCm WSL2 AI Toolkit

Thanks for wanting to help. This project exists because getting AMD GPUs to run AI
tooling on Windows is unnecessarily painful, and the fixes are almost always small
once someone has identified the actual cause.

Read this before opening a pull request. It is short, and it will save you a
rejected PR: two of the rules below (measured performance claims, and the
third-party tool policy) are non-negotiable.

---

## Scope

- **WSL2 only.** Ubuntu 22.04 (jammy) and 24.04 (noble) are the supported
  distributions. Native Linux, Windows-native ROCm and macOS are explicitly out of
  scope — not because they are uninteresting, but because the toolkit is built
  around the ROCDXG GPU bridge that only exists in WSL2, and because untestable
  support claims are worse than none.
- **AMD RDNA3 / RDNA4 and supported Ryzen APUs** (Radeon RX 7000 and 9000 series,
  Ryzen Strix / Strix Halo). Pre-RDNA3 cards are not supported by current ROCm.
- **Bash + Python 3 only.** There is no compiled component in this repository. The
  one native build the toolkit performs is AMD's own `ROCm/librocdxg`, cloned and
  built at install time — never vendored here.

---

## Development setup

Everything happens inside WSL2. You do not need a GPU to work on most of the
codebase.

```bash
# In WSL2 Ubuntu 22.04 or 24.04
git clone https://github.com/daMustermann/rocm-wsl-ai.git
cd rocm-wsl-ai
./install.sh          # checks the environment, installs gum, hands over to the menu
```

Notes:

- **Clone into the Linux filesystem** (`~/rocm-wsl-ai`), not `/mnt/c/...`. Working
  across the 9p mount is several times slower and confuses file permissions and
  executable bits. If you keep the checkout on the Windows side, at least run the
  checks from a Linux-side copy.
- **A GPU is optional for shell and Python work.** `perf_engine.py doctor` is
  designed to run without one, `bash -n`, `shellcheck` and `python3 -m compileall`
  obviously are not affected, and the menu degrades gracefully without ROCm.
- **A GPU is required** for `perf_engine.py probe` / `bench` and for actually
  launching a tool. If you are changing the measurement harness, say in the PR which
  GPU you measured on.
- Optional, but recommended: `sudo apt-get install -y shellcheck`.

You can install a Python virtualenv for the engine's own use, but the engine is
**standard library only** and does not need one. PyTorch lives in the end user's
venv (`~/genai_env`), not in yours.

---

## Running the checks locally

CI runs the same commands (see `.github/workflows/ci.yml`). Please run them before
pushing — a green run locally avoids a review round trip.

```bash
cd ~/rocm-wsl-ai

# 1. Shell syntax
while IFS= read -r -d '' f; do bash -n "$f" || echo "SYNTAX: $f"; done \
    < <(find . -path ./.git -prune -o -name '*.sh' -print0)

# 2. Python syntax
find . -path ./.git -prune -o -name '*.py' -print0 | xargs -0 python3 -m compileall -q

# 3. Lint (warnings and above fail CI)
mapfile -t sh < <(find . -path ./.git -prune -o -name '*.sh' -print | sort)
shellcheck -S warning -e SC1090,SC2010,SC2034,SC2088,SC2155,SC2163 -f gcc "${sh[@]}"

# 4. The performance engine
python3 scripts/utils/perf_engine.py --version    # must print perf_engine <semver>
python3 scripts/utils/perf_engine.py --help
python3 scripts/utils/perf_engine.py doctor       # works without a GPU

# 5. When you have a GPU, and only then
python3 scripts/utils/perf_engine.py probe
python3 scripts/utils/perf_engine.py bench --dry-run
```

The `-e` list in step 3 is a **measured baseline**, not a preference: every code in
it fires somewhere in the existing tree, and each one is explained in a comment in
`.github/workflows/ci.yml`. The list is meant to shrink — if your change fixes one of
those findings, delete the code from both the workflow and this document. Do not add
a code without running shellcheck first and writing down the reason.

One caveat when running locally: the command above lints everything `find` sees,
including scratch scripts you may have in the working tree. CI only ever sees
committed files (`git ls-files -c -o --exclude-standard -- '*.sh'` is the equivalent
list if you want to match CI exactly).

`doctor` exits `1` for environment problems as well as engine problems: on a machine
with no GPU (or no PyTorch) it prints `engine is fine; fix GPU visibility first` or
`engine is fine; PyTorch is not usable yet` and returns `1`. That is expected, and CI
tolerates exactly those two verdicts.

---

## Code style

### Shell

- Start every executable script with `#!/bin/bash` and `set -uo pipefail`.
- **Do not use `set -e` in library files** (`lib/*.sh`). A library must not change
  the error semantics of the shell that sourced it — `lib/common.sh` says so
  explicitly. Guard against double sourcing instead:

  ```bash
  if [ -n "${_ROCM_AI_LAUNCH_LOADED:-}" ]; then
      return 0 2>/dev/null || true
  fi
  _ROCM_AI_LAUNCH_LOADED=1
  ```

- **Never `exit` from a sourced library.** Return a status and let the caller decide.
- **Quote every expansion**: `"$dir"`, `"${array[@]}"`, `"$(command)"`. Use
  `local` for function variables, and prefer `local x` + `x=...` over
  `local x="$(cmd)"` so a failing command's status is not masked.
- **Fail loudly, in the user's language.** Use the existing helpers rather than bare
  `echo`: `ai_err` / `ai_warn` / `ai_info` / `ai_ok` from `lib/launch.sh`, or
  `err` / `warn` / `log` / `success` from `lib/common.sh`. An error should say what
  failed *and* what to do next, e.g.
  `ai_say "     Install it:  ./menu.sh  ->  Install  ->  $name"`.
- **No side effects at source time.** `lib/common.sh` deliberately does no GPU
  detection and writes no files when sourced; the expensive work happens once,
  explicitly, via `ai_load_env` / `ai_preflight`.
- Comments explain *why*, not *what*. The most valuable comments in this codebase
  record what the previous implementation got wrong and how it was measured (see the
  headers of `lib/launch.sh` and `scripts/utils/auto_tuner.sh`). Please keep that up.
- Add `# shellcheck source=` or `# shellcheck disable=` directives when you must
  silence a finding, and never silence one you have not understood.

### Python

- `scripts/utils/perf_engine.py` must remain **standard library only**. No PyYAML, no
  requests, no numpy. Third-party packages are only ever imported inside the
  benchmark worker, which runs in the user's PyTorch virtualenv, and even there only
  `torch`/`triton`.
- **Python 3.10 compatibility is required.** Ubuntu 22.04 ships 3.10 and is a
  supported target; 3.11+ only features (`tomllib`, `datetime.UTC`, `Self`,
  `ExceptionGroup`, `asyncio.TaskGroup`) cannot be used. Keep
  `from __future__ import annotations` at the top of engine modules so
  `dict[str, Any] | None` annotations stay valid, and do not rely on 3.12-only
  behaviour. CI runs the Python job on both 3.10 and 3.12.
- **Never crash the toolkit.** The engine returns structured results and non-zero
  exit codes with a readable message; a bare traceback in a launcher is a bug in
  itself. Wrap subprocess work in timeouts, and keep every failure path explicit.
- Use `argparse` for CLIs, `Path` over string paths, and keep functions small enough
  to be testable without a GPU.
- Add a subcommand's self-check to `run_doctor()` if it can be validated without
  hardware — that is the engine's own regression test, and it runs in CI.

---

## Adding support for a new AI tool

Two different jobs, and it matters which one you are doing.

### A. A built-in tool (goes in this repository)

1. **Add a registry line** to `ROCM_AI_TOOL_REGISTRY` in `lib/tools.sh`. The format is
   documented in that file's header:

   ```text
   key|Display Name|repo-url|install-dir|venv|launch-entry|port|kind|notes
   ```

   `install-dir` may use `$HOME`; `repo-url` is `-` for anything that is not a git
   clone; fields must not contain a `|`. Full field-by-field reference:
   [docs/ADDING_TOOLS.md](docs/ADDING_TOOLS.md).

2. **Add a start script** in `scripts/start/<tool>.sh`. Keep it thin — all
   environment, preflight, tuning, flag validation and idle hibernation live in
   `lib/launch.sh`. Copy `scripts/start/comfyui.sh` as the template and call
   `ai_launch` with `--name`, `--dir`, `--command`, `--venv`, `--port`, and
   `--allow-extra-args -- "$@"`.

3. **Wire the key up in `lib/tools.sh`.** Two lookups are keyed by tool name and do
   not read the registry:
   - `rocm_ai_start_script_for()` — maps a key to its start script filename.
     Without an entry here your tool silently falls through to `custom.sh`.
   - `rocm_ai_tool_effective_port()` — add a `case` arm if the port is
     user-overridable (see `COMFYUI_PORT` etc. in `user.env`).
   Also add the port variable to the defaults written by `ensure_user_env()` in
   `lib/common.sh` if users are meant to be able to change it.

4. **Add an installer wrapper** at `scripts/install/<tool>.sh`. Installers are now
   thin wrappers: source `_shim.sh`, call `rocm_ai_shim_bootstrap "$SCRIPT_DIR"` and
   then `rocm_ai_shim_install "<key>"`. The single implementation lives in
   `lib/tools.sh::rocm_ai_install_tool`, so the menu and the script cannot drift
   apart. `scripts/install/comfyui.sh` is the template.
   Note that `rocm_ai_pip_filtered()` strips `torch` / `torchvision` / `torchaudio`
   lines out of a tool's requirements file on purpose — pip resolving `torch` from
   PyPI would silently replace the ROCm wheels with the CUDA build.

5. **Document it**: add the tool to the tables in `README.md`, and add an entry to
   `CHANGELOG.md` describing what it is and what you verified.

When you propose a built-in tool, include how you confirmed it actually runs on
ROCm 7.2.3 with a `gfx1100`-class GPU or newer, and note the port it uses so it does
not collide with the existing tools (8188 ComfyUI, 7860 SD.Next/Automatic1111, 7861
kohya_ss, 5000 Text Generation WebUI).

### B. A third-party tool (does not go in this repository)

Any git repository can be registered by the user at runtime, from any host (GitHub,
Codeberg, GitLab, self-hosted). Nothing about that is second-class: the tool then
appears in Install, Launch and Updates, and gets a Windows desktop shortcut.

- From the menu: **Install → Add a third-party tool**.
- Or by appending a registry line to `~/.config/rocm-wsl-ai/tools.local`.

That file is per-machine and is in `.gitignore`. **Do not add user `tools.local`
entries to a PR**, and do not add a repository to the built-in registry just because
one user wants it — the registry is for tools that are broadly useful and openly
hosted.

### The third-party tool policy

The built-in registry deliberately does **not** list face-swap or
likeness-manipulation applications, and no PR adding one will be merged. This is an
editorial decision, not a technical limitation — the generic registry above installs
and runs such tools perfectly well, under a name of the user's choosing.

The reasons are documented in full in the header comment of `lib/tools.sh` and in
[docs/ADDING_TOOLS.md](docs/ADDING_TOOLS.md). In short:

- GitHub's Acceptable Use Policies prohibit non-consensual intimate imagery and
  synthetic or manipulated media intended to mislead.
- A repository that ships an installer for a named face-swap application tends to be
  reported and taken down, whether or not the tool itself is lawful. Bundling one
  would put the toolkit's availability at risk for everyone.
- The registry is generic precisely so that this does not have to be a fight: the
  toolkit stays useful, and stays available.

Please do not submit PRs that work around this (indirect naming, "example" entries,
bundled forks, unpacked archives). By the same token, do not lecture users who
register such tools themselves — they own their machine, their legal obligations,
and the consent of anyone in the images they process.

---

## Performance claims: measure, then claim

This project's most expensive historical mistake was claiming performance wins that
did not exist. An earlier auto-tuner benchmarked a `matmul` + `softmax` that had
nothing to do with diffusion inference, attributed the noise to environment variables
that PyTorch's HIP backend never reads, and told users they were "optimised". The
current engine exists to make that impossible.

So:

- **Every performance number in a PR, README, docstring or comment must come from
  `scripts/utils/perf_engine.py bench` on real hardware**, with the raw output
  included in the PR description.
- **Never guess, never extrapolate, and never quote a number from a forum post,
  a blog, or another GPU.** Assume any unmeasured claim will be wrong.
- **Report the verdict as the engine reports it.** A win under the 3% noise floor
  (`NOISE_FLOOR_PCT`) is reported as inconclusive and nothing is applied; a candidate
  whose spread exceeds 20% of its median (`NOISE_REJECT_RATIO`) is discarded as
  unreliable. If your change lands inside those bands, say "within noise" rather than
  inventing a percentage.
- **Say which machine**: GPU model, ROCm and PyTorch versions, and whether you were
  in WSL2. A number without hardware context is not reproducible.
- **Measure twice, in different candidate orders** (see
  [docs/PERFORMANCE.md](docs/PERFORMANCE.md#measuring-your-own-changes)), and close
  games, browsers and other GPU work first.
- **Do not add environment variables that cannot affect the result.** The engine
  tunes exactly three levers because those three measurably change GPU behaviour:
  VRAM residency, MIOpen convolution find-db mode, and math precision. Allocator
  backend and explicit SDPA kernel selection were tested and reported as noise, so
  they are reported but not tuned. One spelling of the allocator variable
  (`PYTORCH_HIP_ALLOC_CONF`) segfaults torch 2.9.1+rocm7.2.3 — `doctor` fails if the
  engine ever emits it again, and it must stay that way.

---

## Commits and pull requests

- Keep a PR to one concern. A behaviour change plus a whitespace sweep is two PRs.
- Match the existing commit style: an imperative subject line (`fix: stop passing
  --lowvram to every GPU`) with the *reason* in the body, and the measurement if
  there is one.
- Fill in `.github/PULL_REQUEST_TEMPLATE.md`. It asks for `bash -n` on changed shell
  scripts, a passing `perf_engine.py doctor`, the measured numbers behind any
  performance claim, and confirmation that nothing from `~/.config/rocm-wsl-ai/` was
  committed. That last one is easy to trip over: `user.env`, `perf.env`,
  `perf_profile.json`, `tools.local`, `miopen/` and `logs/` are per-machine state and
  are gitignored — keep them out of the diff.
- Update `CHANGELOG.md` for anything user-visible — start an `Unreleased` section at
  the top, or extend the newest version section if that release is not tagged yet.
  A bug fix deserves the same sentence a feature gets: what was broken, and why.
- CI must be green. It runs shellcheck, Python on 3.10 and 3.12, syntax checks, and
  the engine's GPU-less `doctor` self-check.

## Reporting bugs and vulnerabilities

- Bugs: use the
  [bug report form](https://github.com/daMustermann/rocm-wsl-ai/issues/new/choose).
  It asks for the output of `scripts/utils/gpu_diag.sh` and
  `scripts/utils/perf_engine.py probe`, because "the GPU is not visible" and "ROCm is
  not installed" are indistinguishable without it. Try
  [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) first.
- Vulnerabilities: **do not open an issue.** Follow [SECURITY.md](SECURITY.md) and
  report privately through GitHub's security advisories.

## Licence

Contributions are accepted under the MIT licence (see [LICENSE](LICENSE)), with the
third-party notice that file carries. By submitting a PR you confirm you have the
right to contribute the code under those terms.
