# Architecture

How the toolkit is put together, and why. Useful before making changes, and for
understanding where to look when something breaks.

---

## Layers

```text
      menu.sh  ·  upgrade.sh  ·  scripts/start/*.sh  ·  install.sh
                                        │
          ┌──────────────┬──────────────┼──────────────┐
          ▼              ▼              ▼              ▼
      lib/ui.sh    lib/tools.sh    lib/launch.sh   lib/migrate.sh
   presentation &  tool registry &  environment,   configuration
   state display   lifecycle        preflight,     repair for
                                    flags, idle    upgrades
                                    hibernation         │
          │              │              │              │
          └──────────────┴──────┬───────┴──────────────┘
                                ▼
                        lib/version.sh
              version discovery, comparison, caches
                                │
                                ▼
                          lib/common.sh
                colours, logging, prompts, paths
                                │
                                ▼
                   scripts/utils/perf_engine.py
                probe · bench · apply · show · doctor
```

Each layer only depends on the ones below it. `lib/common.sh` performs **no work at
source time** — no GPU detection, no subprocess calls, no config writes. An earlier
version ran GPU auto-detection (shelling out to `rocminfo` and PowerShell) on every
single `source`, which added seconds to startup and wrote files as a side effect of
importing a library.

---

## The files

| File | Responsibility |
|---|---|
| `menu.sh` | The interactive menu. Owns screen flow and nothing else. |
| `upgrade.sh` | The ten-stage automatic upgrade. |
| `lib/common.sh` | Colours, logging, prompts, path constants, version. Zero side effects. |
| `lib/version.sh` | Version discovery from AMD's repositories, comparison, caching, and the login-shell GPU environment. |
| `lib/migrate.sh` | Idempotent repair of configuration left behind by older versions. |
| `lib/launch.sh` | GPU environment, cached preflight, flag validation, idle hibernation, `ai_launch`. |
| `lib/tools.sh` | Tool registry: install, update, launch, shortcuts, custom tools. |
| `lib/ui.sh` | Turns machine state into readable output (home screen, status lines). |
| `scripts/utils/perf_engine.py` | The performance engine. Measurement, scoring, profile persistence. |
| `scripts/start/*.sh` | Thin per-tool launchers built on `ai_launch`. |
| `scripts/install/*.sh` | Per-tool installation wrappers; `setup_pytorch_rocm.sh` owns the base environment. |
| `scripts/utils/*.sh` | Diagnostics, updates, shortcuts, first-run wizard. |
| `scripts/utils/wake_server.py` | The "your tool is waking up" page served on the tool's own port while it hibernates. |
| `VERSION` | Single source of truth for the toolkit version. |

---

## Why versions are discovered, never pinned

Older releases wrote exact wheel filenames into the installer, for example:

```text
torch-2.9.1+rocm7.2.3.lw.gitebc02d69-cp310-cp310-linux_x86_64.whl
```

That filename contains a git hash which changes with **every** ROCm patch release,
so each AMD release invalidated the installer until somebody edited the script by
hand. The same happened with `amdgpu-install`, whose package build number
(`7.2.3.70203-1`) versions independently of ROCm.

`lib/version.sh` instead reads AMD's repository index and answers:

- `va_latest_rocm` — newest release with an apt repo for this Ubuntu version
- `va_best_installable_rocm` — newest release that also has wheels for this Python
- `va_resolve_torch_wheels` — the exact torch/torchvision/torchaudio/triton
  filenames for a release and Python tag
- `va_latest_librocdxg` — newest GitHub release tag for the WSL bridge

Two separate checks, because AMD sometimes publishes a ROCm release before its
PyTorch wheels exist; installing that combination would fail at the environment
rebuild after ROCm had already been replaced. Results are cached for 24 hours and
every resolver has an offline fallback, so an unreachable network degrades to a
known-good version rather than failing.

### Enforcement

The CI and verification suite greps the install and upgrade paths for hardcoded
version strings, so this property is tested rather than merely intended.

---

## The GPU environment problem

This is the most important correctness detail in the codebase, and the reason
`lib/launch.sh` exists.

For ROCm to see the GPU inside WSL2, `HSA_ENABLE_DXG_DETECTION=1` must be set
**before the Python process starts**. It is not a hint — without it, libhsa
enumerates zero GPU agents and `torch.cuda.is_available()` returns `False`.

Measured on `gfx1100`:

```text
$ python3 -c "import torch; print(torch.cuda.is_available())"
False
$ HSA_ENABLE_DXG_DETECTION=1 python3 -c "import torch; print(torch.cuda.is_available())"
True
```

`rocminfo` reports the GPU either way, because it takes a different code path. So
every naive diagnostic says the hardware is fine while PyTorch sees nothing.

The previous implementation appended the variable to the virtualenv's `activate`
script. That works only if you source `activate` first, so the GPU vanished in a
fresh shell, from an IDE, from a script, or from any tool that did not activate the
venv. `ai_load_env` now exports the complete GPU environment explicitly, and it runs
first in every launch path.

### Related: `HSA_OVERRIDE_GFX_VERSION`

With ROCDXG installed, this variable must **not** be set. DXCore enumerates the GPU
and determines its own architecture; an override makes
`topology_sysfs_get_node_props` reject the value and the GPU becomes invisible.
`ai_load_env` unsets it when `librocdxg` is present, which is why the Settings menu
warns loudly about setting it manually.

---

## Preflight caching

The GPU check is a few seconds of `import torch`. Running it on every launch is
wasteful; skipping it entirely means users see Python tracebacks instead of a fix
list. The compromise:

1. A signature is computed from the torch version, the Windows driver version, and
   ROCDXG presence.
2. If the cached signature matches and the result was healthy, the check is skipped.
3. Inside `ROCM_AI_PREFLIGHT_TTL` (default 900 s) even the signature computation is
   skipped, since that alone shells out to Python and PowerShell.
4. A cached **failure** is never trusted, so fixing the problem and relaunching
   re-checks immediately.

Measured: **~2.5 s** cold, **~4 ms** warm, versus ~2.5 s on every launch before.

---

## Flag validation

ComfyUI's CLI grows across releases. A flag from a newer version makes an older
checkout exit immediately with an opaque error. So before passing tuned flags,
`lib/launch.sh` reads the installed ComfyUI's real `main.py --help` output and drops
anything it does not recognise:

```text
⚠  Dropping unsupported ComfyUI flag for this version: --vram-headroom
```

The probe costs ~20 ms and only runs when there are flags to validate.

---

## Profiles and persistence

A tuned profile is written in two forms, both under `~/.config/rocm-wsl-ai/`:

- **`perf_profile.json`** — full provenance: the profile, the environment it
  produces, the ComfyUI arguments, and the metrics measured. Read by tooling.
- **`perf.env`** — shell-consumable exports, sourced by `ai_load_env`. Every name is
  namespaced (`ROCM_AI_*`, `MIOPEN_*`, `HSA_*`) so a stale file can never leak a
  wrong export into a launcher.

`perf_engine.py` is the only writer of either. Hand-editing them is pointless — the
next `apply` overwrites them. Edit `user.env` instead, which the launcher layers
*under* the profile.

### Environment layering order

`ai_load_env` applies, in order:

1. `user.env` — your settings (ports, idle timeout, overrides)
2. `gpu.env` — auto-detected GPU environment
3. `perf.env` — the tuned profile
4. Non-negotiable requirements (`HSA_ENABLE_DXG_DETECTION=1`, `PIP_USER=0`, the
   ROCDXG override guard)
5. The `PYTORCH_HIP_ALLOC_CONF` trap door — stripped and warned about

Applied last so nothing below can undermine the requirements.

---

## Idle hibernation

Formerly "Smart Sleep", previously implemented by spawning a `smart_sleep_wrapper.py`
process, which itself spawned the tool, and then `wake_server.py`. That is two extra
Python interpreters — roughly 150 MB of RAM — purely to watch for idleness. The
wrapper and the old `benchmark.py` were deleted in 4.0.0.

It is now about 40 lines of bash in `ai_run_with_hibernation`:

1. Run the tool with its output piped through `tee`.
2. Watch the log file's mtime for activity.
3. On timeout, `SIGINT` the process, escalating to `SIGKILL` after 10 s.
4. Serve the wake page on the same port until somebody visits it.
5. Restart the tool and go back to watching.

`SIGINT` is forwarded so Ctrl+C still reaches the tool the way it always did.
`wake_server.py` remains, because the wake page genuinely needs an HTTP server and
it is only alive while the tool is asleep.

---

## The performance engine

`scripts/utils/perf_engine.py`, standard library only, Python 3.10+.

### Why the bound is subprocesses

Every candidate runs in its own subprocess. A driver hang, an out-of-memory
condition or a segfault kills only that candidate, and the engine records a failure
and moves on. This is not theoretical: it is exactly how the
`PYTORCH_HIP_ALLOC_CONF` segfault was discovered — as a clean per-candidate failure
rather than a dead tuner.

### Measurement discipline

Three measurement traps are actively defended against, each of which produced a
confidently wrong result before it was found:

| Trap | Symptom | Defence |
|---|---|---|
| Wrong dtype | Fused attention read 15.7 ms instead of 2.9 ms; `MATH` looked fastest | `"auto"` precision resolves to bf16 with an fp16 fallback, verified on-device |
| GPU cold state | First denoise loop 104 ms/step vs 16 ms for the same config | A warm-up pass whose result is measured and discarded |
| Drift across the sweep | Reference configuration varied 43% start-to-finish | Reference measured before and after; a 25% difference discards the run |

Measurements are also grouped so that workloads cannot contaminate each other, and
each candidate gets a private MIOpen cache directory so "cold start" is genuinely
cold.

### Profile model

Profiles are declarative dictionary patches over `PROFILE_BASE`, so the diff between
any two candidates is obvious in `--dry-run`. Only levers that measurably change GPU
behaviour are modelled: VRAM residency, MIOpen find-db mode, and precision.
`PROFILE_SPECS` is the place to extend.

Attention does **not** contribute to scoring. No profile changes the attention
kernel, and attention measured inside a long benchmark process inflates badly. It
is measured once in a dedicated clean process and reported as information, which is
what makes the kernel table trustworthy.

### Honesty rules

Implemented in `rank_results`:

- Numerical validation against an eager reference; wrong kernels are rejected.
- Candidates with a spread above 20% of their median are discarded as noise.
- A win below 3% is reported as inconclusive and nothing is applied.
- Candidates within 4% of each other are a tie, and `VRAM_MODE_SAFETY` picks the
  least aggressive one.

### Doctor

`run_doctor()` verifies the engine without a GPU. Critically, it includes a
**torch boot test** — it launches PyTorch under a real profile environment and fails
if that does not succeed — and a `compile()` check of both embedded workers, whose
source lives inside string literals and is therefore invisible to a normal syntax
check. That check exists because an indentation mistake inside `BENCH_WORKER` got
through a clean `py_compile` of the module and only surfaced at benchmark time.

---

## The upgrade path

`upgrade.sh` is deliberately a *sequence of independent stages* rather than one
long procedure. Each stage re-checks the current state before acting, so the script
is safe to re-run after any failure and will skip whatever already succeeded.

```text
detect → report → toolkit → migrate → shell env → ROCm → ROCDXG
       → python env → tools → retune → verify
```

Two ordering details matter:

- **The toolkit updates first, and then the script re-executes itself.** A running
  bash process holds the old library code in memory; after a `git pull` the rest of
  the run would otherwise mix old logic with new files. Re-exec is guarded by
  `ROCM_AI_REEXEC` so it cannot loop.
- **Migration runs before anything reads configuration.** `PYTORCH_HIP_ALLOC_CONF`
  and a stale `HSA_OVERRIDE_GFX_VERSION` both break PyTorch at import or device
  enumeration, so repairing them after the environment rebuild would hide the
  result behind a confusing failure.

`lib/migrate.sh` is written to be idempotent, because "safe to re-run" is only true
if a second pass is a no-op. Each function detects its own condition and backs the
file up before editing.

---

## Conventions
- **Libraries use `set -uo pipefail`, not `set -e`.** A library should not silently
  terminate its caller's shell. Executable scripts may use `set -e` locally.
- **Quote everything.** Paths here routinely contain spaces, especially on `/mnt/c`.
- **`printf` over `echo -e`.** `echo` behaviour varies; `printf` does not.
- **Errors go to stderr**, so callers can capture stdout safely.
- **Every failure names the fix.** A message like "ROCDXG is missing" is a bug
  report; "ROCDXG is missing — run Install → Upgrade / repair ROCDXG" is a solution.
- **Python stays 3.10-compatible**, because Ubuntu 22.04 ships 3.10 and is a
  supported target.

---

## Adding a new tool

See [`ADDING_TOOLS.md`](ADDING_TOOLS.md). In short: one registry line in
`lib/tools.sh`, plus a `scripts/start/<tool>.sh` built on `ai_launch`. Most tools
need roughly twenty lines.
