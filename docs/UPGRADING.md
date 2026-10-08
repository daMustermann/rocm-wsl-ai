# Upgrading to 5.0 (ROCm 10.1)

If you are on 4.x or older, there is **one command**:

```bash
cd ~/rocm-wsl-ai
./upgrade.sh
```

It brings ROCm to 10.1, rebuilds PyTorch against it, repairs settings the old
version left behind, reinstalls your tools' dependencies, re-measures
performance, and verifies the result.

**Your models, custom nodes, extensions and datasets are never touched.**

---

## Read this part first

**This upgrade is destructive, and it is not the same kind of upgrade 4.x users
have run before.**

AMD requires ROCm 7.2.x or older to be **uninstalled** before ROCm 10.x can be
installed. The two package trees both register `/opt/rocm` through
`update-alternatives`, and AMD's own documentation states the requirement without
giving commands. So the upgrade has to remove your working ROCm 7.2.x packages
before it can install 10.1.

What that means in practice:

- **Your `/opt/rocm-7.2.x` directories are renamed, not deleted.** They become
  `/opt/rocm-7.2.4.retired-<timestamp>`. Nothing is destroyed, and a rollback is
  possible (see [Rolling back](#rolling-back-to-72x)).
- **Your `~/genai_env` is moved aside**, to `~/genai_env_backup_<timestamp>`,
  before the new one is built.
- **You are asked to type `REMOVE`** before any package is touched. A stray Enter
  keypress is not enough.
- **WSL support in ROCm 10.x is a technical preview.** It works — it is what this
  project is tested against — but AMD lists known issues, and if the preview
  misbehaves on your machine, the 7.2.x path is still maintained.

If any of that is not what you want, **stay where you are**:

```bash
./upgrade.sh --target legacy
```

That keeps ROCm 7.2.x, including the from-source `librocdxg` build, and remains
fully supported.

### Before you start

| Requirement | Why |
|---|---|
| **AMD Adrenalin 26.10.41.05+** | New. ROCm 10.x requires it; 4.x required 26.2.2. Check with **Settings → GPU Diagnostics** |
| **Internet connection** | ROCm and PyTorch are several GB |
| **~20 GB free disk** | The new environment is built before the old one is removed |
| **20–40 minutes** | Mostly download time |
| ~~Windows SDK~~ | **No longer needed.** ROCm 10.x ships the WSL GPU bridge itself |

---

## Not sure if you need to upgrade?

```bash
./upgrade.sh --check
```

Changes nothing. Prints exactly what would happen:

```text
   COMPONENT              INSTALLED                  AVAILABLE
   ────────────────────────────────────────────────────────────────────

   Target ROCm 10.1 core channel · architecture gfx1100

   Toolkit                4.1.0                      5.0.0   <- update
   Legacy ROCm 7.2.x      legacy                     will be REMOVED   <- destructive
   ROCm                   7.2.4                      amdrocm10.1-gfx1100   <- install
   ROCDXG (WSL bridge)    1.2.2                      ships with ROCm
   PyTorch                2.10.0+rocm7.2.4.git3d3…   rebuild for ROCm 10.1
   Configuration          current                    up to date
   Login-shell GPU env    installed                  up to date
   ────────────────────────────────────────────────────────────────────

   DESTRUCTIVE This upgrade removes your working ROCm 7.2.x packages.
               AMD requires it: both stacks register /opt/rocm and
               cannot coexist. Your /opt/rocm-7.2.x directories are
               set aside, not deleted, so a rollback stays possible.
               You will be asked to type REMOVE before anything goes.

   3 component(s) will be updated.
```

You can also see this in the menu: **Updates** shows a one-line summary, and the
home screen tells you when an upgrade is available.

---

## What the upgrade actually does

Stages run in order, and any that is already done is skipped — so it is safe to
re-run after a failure.

| # | Stage | What happens |
|---|---|---|
| 1 | **Detect** | Asks AMD what is available; works out your GPU architecture and which ROCm series has wheels for your Python |
| 2 | **Report** | One table of installed vs available, and asks before changing anything |
| 3 | **Toolkit** | `git pull`, then restarts itself with the new code |
| 4 | **Migrate** | Repairs settings from older versions that are stale or actively harmful |
| 5 | **Shell** | Installs the GPU environment so PyTorch finds your GPU from any terminal |
| 6 | **Remove legacy** | **The destructive stage.** Purges the 7.2.x packages and renames `/opt/rocm-7.2.x` aside |
| 7 | **ROCm** | Installs `amdrocm10.1-gfx<arch>` from AMD's signed repository |
| 8 | **Environment** | Rebuilds `~/genai_env` with `pip`-resolved PyTorch |
| 9 | **Tools** | Reinstalls every tool's dependencies against the new stack |
| 10 | **Retune** | Re-measures performance, because the old profile is now stale |
| 11 | **Verify** | Confirms PyTorch sees the GPU, and prints the final version table |

### Why the ROCDXG stage disappeared

On 4.x, the WSL GPU bridge (`librocdxg`) was versioned separately from ROCm and
had to be **compiled from source against the Windows SDK**. That was the single
most fragile part of the install: a missing Windows SDK aborted it, and a
mismatched SDK produced a bridge that made `rocminfo` see a GPU PyTorch could not.

ROCm 10.x ships the bridge itself (v1.1.0 on this release), and the ROCr runtime
loads it automatically when it finds `/dev/dxg`. There is nothing to build, no
SDK to install, and no `HSA_ENABLE_DXG_DETECTION` export to get wrong. The
confirmation that it is working is one line:

```bash
rocminfo | grep -i wsl     # WSL environment detected.
```

### Why it re-tunes

Performance settings are hardware- *and* driver-specific. A profile measured
against ROCm 7.2.4 is not valid for 10.1 — the runtime, the maths libraries and
the allocator all changed. The stale profile is removed and the tuner re-runs, so
you are not left with settings that look tuned but were never measured on what
you are actually running.

Use `--no-retune` to skip it and run it later from **Performance → Auto-tune**.

---

## What gets migrated, and why it matters

Upgrading the code is only half the job. A machine that has run 3.x or 4.x
carries settings that would quietly undo the 5.0 fixes:

| Old setting | What the upgrade does | Why |
|---|---|---|
| `PYTORCH_HIP_ALLOC_CONF` in your venv's `activate`, `.bashrc`, or `user.env` | Comments it out | **It segfaults PyTorch on import** (measured on 2.9.1 and 2.10.0). Older versions wrote it there deliberately |
| `HSA_OVERRIDE_GFX_VERSION` anywhere | Removed, and `user.env` now says why | Under WSL it makes the runtime reject the device, **hiding your GPU entirely**. It is not a fallback setting |
| `~/.genai_opt_profile` | Renamed to `.obsolete-3.x` | Its `MIGRAPHX_MLIR_USE_SPECIFIC_OPS` values have no effect on PyTorch's HIP backend |
| `perf.env` / `perf_profile.json` | Deleted | Measured against the old ROCm; carrying it forward would be a lie |
| Stale `.preflight`, `.gpu_summary`, `.engine_summary` caches | Deleted | They hold results computed with the old, wrong configuration |
| The legacy `rocm` apt source | Removed with the packages | Otherwise apt keeps offering superseded ROCm on every update |
| `user.env` missing `AMDROCM_DEVICE_TARGET` | Written on first 10.1 install | Records which architecture to use, so a future upgrade keeps the same one |

Every file that changes is **backed up** next to the original with a
`.pre-<version>.<timestamp>` suffix. Nothing is edited destructively, and the
migration is idempotent — running it twice changes nothing the second time.

---

## Command-line options

| Command | Effect |
|---|---|
| `./upgrade.sh` | Check, then upgrade what needs it, with prompts |
| `./upgrade.sh --check` | Report only. Changes nothing |
| `./upgrade.sh --yes` | No prompts — for scripted or unattended use |
| `./upgrade.sh --force` | Reinstall everything even if versions look current |
| `./upgrade.sh --target core` | Move to ROCm 10.x. **This is the default** |
| `./upgrade.sh --target legacy` | Stay on the ROCm 7.2.x channel |
| `./upgrade.sh --rocm-only` | Skip the toolkit self-update |
| `./upgrade.sh --no-retune` | Skip re-measuring performance |

Non-interactive example:

```bash
cd ~/rocm-wsl-ai && git pull && ./upgrade.sh --yes
```

---

## After the upgrade: restart WSL

**This step is required.** Group membership is only re-established when WSL
restarts, and the new ROCm needs to load its bridge library.

In Windows PowerShell or CMD:

```powershell
wsl --shutdown
```

Then reopen Ubuntu and run:

```bash
./menu.sh
```

The upgrade tells you this at the end, and it is normal for the final
verification to report that the GPU is not usable yet *before* the restart.

To confirm afterwards:

```bash
rocminfo | grep -i wsl
~/genai_env/bin/python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
```

You are looking for `WSL environment detected.` and `True`.

---

## If something goes wrong

### The GPU is not visible after upgrading

Almost always the missing restart. Run `wsl --shutdown` and try again.

If it persists, **Settings → GPU Diagnostics** checks the driver version, the
`/dev/dxg` device, the bridge library, group membership, the environment
variables and the venv, in that order, and prints the fix for whichever is wrong.

### `No matching distribution found for torch`

Almost always the wrong `device-*` extra — a mismatch between the apt package's
architecture and the torch extra. Check what is installed:

```bash
dpkg -l | grep amdrocm10.1
```

If you are unsure which architecture is right, the universal extra works at the
cost of a larger download:

```bash
~/genai_env/bin/pip install --index-url https://stable.repo.amd.com/rocm/whl-next/ \
    'rocm[libraries,device-all]' 'torch[device-all]'
```

### `amd-smi event` hangs

Known ROCm 10.1 WSL issue — the `event` subcommand is not supported there and
may not return. Do not run it. `amd-smi static` and `amd-smi metric` do work.

### A HIP device-side assertion hangs

Also a known 10.1 WSL issue: certain device-side executions can leave the
workload stopped while the host process waits. Most HIP and OpenCL workloads are
unaffected. If you hit it, terminate the process and restart.

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

### It says it could not resolve a ROCm release

You are probably offline, or AMD's index is unreachable. The upgrade caches its
version lookups for 24 hours, so it can usually proceed from cache. To retry with
fresh data:

```bash
rm -rf ~/.config/rocm-wsl-ai/cache
./upgrade.sh --check
```

---

## Rolling back to 7.2.x

Nothing was deleted, so this is possible. You will need root, and the legacy
packages have to be reinstalled because `apt purge` removed them.

```bash
# 1. Find what was set aside
ls -d /opt/rocm-7.2.*.retired-*

# 2. Move it back
sudo mv /opt/rocm-7.2.4.retired-<timestamp> /opt/rocm-7.2.4

# 3. Reinstall the legacy ROCm stack from AMD's 7.2.x repository
#    (see docs/WSL2_SETUP_GUIDE.md -> Staying on ROCm 7.2.x)

# 4. Restore your Python environment
mv ~/genai_env_backup_<timestamp> ~/genai_env

# 5. Rebuild the WSL bridge, which needs the Windows SDK
#    (see docs/WSL2_SETUP_GUIDE.md -> Staying on ROCm 7.2.x)

# 6. Keep the toolkit on the legacy channel from now on
./upgrade.sh --target legacy
```

You can also stay on 7.2.x without rolling back at all — just never run the
upgrade, and use `--target legacy` if you do:

```bash
cd ~/rocm-wsl-ai && git checkout v4.1.0
```

---

## For users coming from a specific version

### From 4.x

The main case this document describes. The additional work over a normal version
bump is the legacy teardown and the architecture-specific package.

### From 3.4.0 or 4.0.x

Identical — the migration table above covers everything those versions leave
behind, including `PYTORCH_HIP_ALLOC_CONF` and the retired
`~/.genai_opt_profile`.

### From 3.0.x – 3.3.x

The same, plus the broken desktop `.bat` shortcuts from before 3.3.0, which are
renamed to `.broken-backup`. They used malformed `wsl.exe` arguments and closed
instantly.

---

## Why versions are not pinned

Older releases baked exact wheel filenames into the installer, for example:

```text
torch-2.9.1+rocm7.2.3.lw.gitebc02d69-cp310-cp310-linux_x86_64.whl
```

Those filenames contain a git hash that changes with **every** ROCm patch
release, so a new ROCm version required editing the installer by hand.

The toolkit now reads AMD's repository index at run time and resolves:

- the newest ROCm series published for your Ubuntu release,
- that series' newest PyTorch build for **your** Python version,
- the `device-*` extra matching your GPU architecture.

The practical consequence: **new ROCm releases work without a toolkit update.**
`./upgrade.sh --check` will offer them as soon as AMD publishes them.

CI enforces this. The `no-pinned-versions` job fails the build if a ROCm
repository URL, a wheel directory or a version number is written into code
anywhere outside `lib/version.sh`, and if the `VERSION` file and the README badge
disagree. It exists because this class of rot has bitten the project twice.

If AMD's repositories are unreachable, the toolkit falls back to a known-good
version so an offline machine still works.