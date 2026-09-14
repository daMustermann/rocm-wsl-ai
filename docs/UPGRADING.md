# Upgrading to v4.1

If you are on an older version of this toolkit, there is **one command**:

```bash
cd ~/rocm-wsl-ai
./upgrade.sh
```

That is it. It updates the toolkit, brings ROCm to the newest release AMD
publishes, rebuilds PyTorch against it, repairs settings the old version left
behind, reinstalls your tools' dependencies, re-measures performance, and verifies
the result.

**Your models, custom nodes, extensions and datasets are never touched.**

---

## Not sure if you need to upgrade?

```bash
./upgrade.sh --check
```

Changes nothing. Prints exactly what would happen:

```text
   COMPONENT              INSTALLED                  AVAILABLE
   ────────────────────────────────────────────────────────────────────
   Toolkit                3.4.0                      4.1.0   <- update
   ROCm                   7.2.3                      7.2.4   <- upgrade
   ROCDXG (WSL bridge)    1.2.0                      v1.2.2   <- rebuild
   PyTorch                2.9.1+rocm7.2.3...         rebuild for ROCm 7.2.4
   Configuration          3.x-era settings           needs migrating
   Login-shell GPU env    not installed              will install
   ────────────────────────────────────────────────────────────────────

   6 component(s) will be updated.
```

You can also see this in the menu: **Updates** shows a one-line summary, and the
home screen tells you when a newer ROCm is available.

---

## What the upgrade actually does

It runs ten stages in order, skipping any that are already done.

| # | Stage | What happens |
|---|---|---|
| 1 | **Detect** | Queries AMD's repositories for the newest ROCm release and checks what you have |
| 2 | **Report** | Shows one table of installed vs available, and asks before changing anything |
| 3 | **Toolkit** | `git pull` to the latest release, then restarts itself with the new code |
| 4 | **Migrate** | Repairs settings from older versions that are stale or actively harmful |
| 5 | **Shell** | Installs the GPU environment so PyTorch finds your GPU from any terminal |
| 6 | **ROCm** | Points apt at the newest release and upgrades |
| 7 | **ROCDXG** | Rebuilds the WSL GPU bridge from the newest tag |
| 8 | **Environment** | Rebuilds `~/genai_env` with matching PyTorch wheels |
| 9 | **Tools** | Reinstalls every tool's dependencies against the new stack |
| 10 | **Retune** | Re-measures performance, because the old profile is now stale |

### Why it re-tunes

Performance settings are hardware- *and* driver-specific. A profile measured
against ROCm 7.2.3 is not valid for 7.2.4, so the stale profile is removed and the
tuner re-runs. Skipping this would leave you with settings that look tuned but
have not been measured on what you are actually running.

Use `--no-retune` to skip it and run it later from **Performance → Auto-tune**.

### Why it rebuilds ROCDXG

The WSL GPU bridge is versioned separately from ROCm. v1.2.2 fixes issues in
v1.2.0 and is built from source, so the upgrade clones the newest tag and rebuilds
it. If the Windows SDK is missing, this step is skipped with instructions and your
existing bridge keeps working.

---

## What gets migrated, and why it matters

Upgrading the code is only half the job. A machine that has run 3.x carries
settings that would quietly undo the 4.x fixes:

| Old setting | What the upgrade does | Why |
|---|---|---|
| `PYTORCH_HIP_ALLOC_CONF` in your venv's `activate`, `.bashrc`, or `user.env` | Comments it out | **It segfaults PyTorch 2.9.1+rocm7.2.3 on import.** Older versions wrote it there deliberately |
| `~/.genai_opt_profile` | Renamed to `.obsolete-3.x` | Its `MIGRAPHX_MLIR_USE_SPECIFIC_OPS` and `PYTORCH_ALLOC_CONF` values have no effect on PyTorch's HIP backend |
| `HSA_OVERRIDE_GFX_VERSION` in `gpu.env` | Removed | With ROCDXG installed it makes the runtime reject the device, **hiding your GPU entirely** |
| Stale `.preflight`, `.gpu_summary`, `.engine_summary` caches | Deleted | They hold results computed with the old, wrong configuration |
| `user.env` missing `TEXTGEN_PORT`, `SMART_SLEEP_TIMEOUT` | Appended | New settings introduced in 4.x |
| Broken desktop `.bat` files from before 3.3.0 | Renamed to `.broken-backup` | They used malformed `wsl.exe` arguments and closed instantly |

Every file that changes is **backed up** next to the original with a
`.pre-4.1.<timestamp>` suffix. Nothing is edited destructively, and the migration is
idempotent — running it twice changes nothing the second time.

You can trigger just the migration without touching ROCm:

```bash
./menu.sh     # then: Settings -> (migration runs automatically on upgrade)
```

---

## Command-line options

| Command | Effect |
|---|---|
| `./upgrade.sh` | Check, then upgrade what needs it, with prompts |
| `./upgrade.sh --check` | Report only. Changes nothing |
| `./upgrade.sh --yes` | No prompts — for scripted or unattended use |
| `./upgrade.sh --force` | Reinstall everything even if versions look current |
| `./upgrade.sh --rocm-only` | Skip the toolkit self-update |
| `./upgrade.sh --no-retune` | Skip re-measuring performance |

Non-interactive example:

```bash
cd ~/rocm-wsl-ai && git pull && ./upgrade.sh --yes
```

---

## What you will need

| Requirement | Why |
|---|---|
| **Internet connection** | ROCm and PyTorch are several GB in total |
| **~15 GB free disk** | The new environment is built before the old one is removed |
| **Windows SDK** | Needed to rebuild ROCDXG. The upgrade continues without it |
| **AMD Adrenalin 26.2.2+** | Unchanged requirement |
| **20–40 minutes** | Mostly download time |

The old environment is **moved aside, not deleted**, to
`~/genai_env_backup_<timestamp>`. Once you have confirmed everything works:

```bash
rm -rf ~/genai_env_backup_*
```

---

## After the upgrade: restart WSL

**This step is required.** ROCm changed, and the GPU bridge and group membership are
only re-established when WSL restarts.

In Windows PowerShell or CMD:

```powershell
wsl --shutdown
```

Then reopen Ubuntu and run:

```bash
./menu.sh
```

The upgrade tells you this at the end, and it is normal for the final verification
to report that the GPU is not usable yet *before* the restart.

---

## If something goes wrong

Upgrades are designed so that a failure is recoverable rather than destructive.

### The GPU is not visible after upgrading

Almost always the missing restart. Run `wsl --shutdown` and try again.

If it persists:

```bash
./menu.sh          # Settings -> GPU Diagnostics
```

### The new environment is broken

Your previous one is intact:

```bash
rm -rf ~/genai_env
mv ~/genai_env_backup_<timestamp> ~/genai_env
```

Then re-run `./upgrade.sh` once you have resolved whatever failed.

### A tool stopped working after its dependencies were reinstalled

Reinstall that tool from the menu (**Install → the tool name**). Your models and
custom nodes live outside the Python environment and are unaffected.

### The upgrade stopped partway

Safe to re-run — every stage detects what is already done and skips it:

```bash
./upgrade.sh
```

The full log of the last run is at:

```bash
ls -t ~/.config/rocm-wsl-ai/logs/upgrade-*.log | head -1
```

### It says "Could not find PyTorch wheels for ROCm X"

You are probably offline. The upgrade caches its version lookups for 24 hours, so
it can usually proceed from cache. To retry with fresh data:

```bash
rm -rf ~/.config/rocm-wsl-ai/cache
./upgrade.sh --check
```

### Undoing the whole upgrade

Every migration backup is reversible, and the toolkit itself is a git checkout:

```bash
git -C ~/rocm-wsl-ai log --oneline -5
git -C ~/rocm-wsl-ai checkout <previous-commit>
```

Note that ROCm itself is a system package; going *backwards* would mean pointing
apt at the older release and reinstalling, which is why the upgrade prefers
forward-only.

---

## For users coming from a specific version

### From 3.0.x or 3.1.x

The upgrade handles the ROCm 7.2.1 → 7.2.4 jump, including rebuilding ROCDXG.
Everything in the migration table above applies. Expect a longer run — this is the
largest jump.

### From 3.2.x or 3.3.x

Straightforward. The main migration is `PYTORCH_HIP_ALLOC_CONF` (if you ever ran
the old updater) and retiring `~/.genai_opt_profile`.

### From 3.4.0

The toolkit update plus the migration. The performance tuning from 3.4.0 did not
do anything measurable, so expect the tuner to produce genuinely different — and
now measured — settings.

### From 4.0.0

```bash
./upgrade.sh
```

This brings you ROCm 7.2.4, the newest ROCDXG, and PyTorch 2.10, plus the
login-shell environment fix. If you installed 4.0.0 by hand, note that 4.1 also
switches the base installer from the `amdgpu-install` package (which needed a
hardcoded build number that broke on every AMD republish) to AMD's signed apt
repository directly.

---

## Why the version numbers are no longer pinned

Older releases baked exact wheel filenames into the installer, for example:

```text
torch-2.9.1+rocm7.2.3.lw.gitebc02d69-cp310-cp310-linux_x86_64.whl
```

Those filenames contain a git hash that changes with **every** ROCm patch release,
which meant a new ROCm version required editing the installer by hand. The toolkit
now reads AMD's repository index at run time, picks the newest release that has an
apt repository for your Ubuntu version *and* PyTorch wheels for your Python
version, and downloads exactly those files.

The practical consequence: **new ROCm releases work without a toolkit update.**
`./upgrade.sh --check` will offer them as soon as AMD publishes them.

If AMD's repositories are unreachable, the toolkit falls back to a known-good
version so an offline machine still works.
