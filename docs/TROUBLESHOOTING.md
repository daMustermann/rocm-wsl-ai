# Troubleshooting

Start here for anything that is broken:

```bash
./menu.sh                 # Settings -> GPU diagnostics
scripts/utils/perf_engine.py probe     # what does PyTorch actually see?
scripts/utils/perf_engine.py doctor    # self-check the toolkit itself
```

`GPU diagnostics` is the full check. `perf_engine.py doctor` verifies the toolkit's
own machinery and works even with no GPU present.

---

## "PyTorch can't see my GPU"

Symptom: `torch.cuda.is_available()` returns `False`, or a tool prints that it
found no CUDA/ROCm device — while `rocminfo` happily lists your Radeon.

This is the single most common failure, and it has a specific cause on this stack:
**`HSA_ENABLE_DXG_DETECTION` must be `1` before the Python process starts.**

```text
$ python3 -c "import torch; print(torch.cuda.is_available())"
False

$ HSA_ENABLE_DXG_DETECTION=1 python3 -c "import torch; print(torch.cuda.is_available())"
True
```

`rocminfo` reports the GPU either way, which is why naive diagnostics look fine.

Run through this in order:

1. **Did you restart WSL after the base install?** This is the most common answer.
   In Windows PowerShell or CMD:

   ```powershell
   wsl --shutdown
   ```

   Then reopen Ubuntu. Group membership and the DXCore bridge are only applied to a
   new session.

2. **Can WSL reach the GPU at all?**

   ```bash
   ls -l /dev/dxg
   ```

   This must be a character device. If it is missing, **nothing else matters** —
   no ROCm install can make a GPU appear, and PyTorch will never see one. It means
   the Windows driver is not exposing DXCore, which usually means an out-of-date
   driver or a WSL instance that was not restarted.

3. **Is the GPU bridge present?** ROCm 10.x ships it inside ROCm and the runtime
   loads it automatically, so this only ever fails if the ROCm package did not
   install correctly:

   ```bash
   rocminfo | grep -i wsl        # want: WSL environment detected.
   ls -l /opt/rocm/core-*/lib/librocdxg.so
   ```

   A much better one-line check is the `rocminfo` grep above: it proves the
   runtime actually *loaded* the bridge, rather than merely finding the file.
   If it fails, re-run **Install → Repair / reinstall the base environment**.

   > On ROCm 7.2.x this library had to be compiled from source against the
   > Windows SDK, and lived at `/opt/rocm/lib/librocdxg.so`. If you are still on
   > the legacy channel that path is correct; on 10.x it has moved.

4. **Are you in the `render` and `video` groups?**

   ```bash
   id -nG | tr ' ' '\n' | grep -E 'render|video'
   ```

   If not:

   ```bash
   sudo usermod -a -G render,video "$USER"
   ```

   …then `wsl --shutdown` and reopen.

5. **Is the Windows driver new enough?** AMD Adrenalin **26.10.41.05** or newer is
   required by ROCm 10.x. Check with `Settings → GPU diagnostics`, which queries
   the Windows driver version and compares it.

6. **Is the environment actually loaded?** If you are running Python by hand:

   ```bash
   source ~/genai_env/bin/activate     # the launcher does this for you
   ```

   Launching through `./menu.sh` or `scripts/start/*.sh` sets the full GPU
   environment explicitly and does not depend on activation.

> **A specific trap:** if `PYTORCH_HIP_ALLOC_CONF` is set anywhere in your shell
> (`~/.bashrc`, `~/.profile`, an old `user.env`), PyTorch **segfaults** on import
> instead of reporting an error. The launcher strips it and warns you; remove it
> from wherever it is set. See [`PERFORMANCE.md`](PERFORMANCE.md).

> **The other trap:** if `HSA_OVERRIDE_GFX_VERSION` **is** set, the runtime
> *rejects* your device. `rocminfo` still lists the GPU, PyTorch reports none.
> It is not a workaround. Check and unset it:
>
> ```bash
> echo "${HSA_OVERRIDE_GFX_VERSION:-<unset>}"
> sed -i '/HSA_OVERRIDE_GFX_VERSION/d' ~/.config/rocm-wsl-ai/user.env
> ```

---

## Base install fails

### `librocdxg` is missing

On ROCm 10.x this library ships inside ROCm, so a missing copy means the ROCm
package did not install:

```bash
dpkg -l | grep amdrocm10.1
ls -d /opt/rocm/core-*
```

Re-run **Install → Repair / reinstall the base environment**.

If you are on the **legacy 7.2.x channel**, this library is built from source and
does need the Windows SDK — see
[WSL2_SETUP_GUIDE.md → Staying on ROCm 7.2.x](WSL2_SETUP_GUIDE.md#staying-on-rocm-72x).

### ROCm package installation fails or downloads stall

`stable.repo.amd.com` can be slow or briefly unavailable.

```bash
sudo apt update
sudo apt install -y amdrocm10.1-gfx1100    # substitute your architecture
```

Re-running is safe. Partially installed packages resume. Confirm the repository
is configured as AMD documents it:

```bash
cat /etc/apt/sources.list.d/amdrocm-stable.sources
```

If `apt update` reports a missing `Signed-By` key, the keyring did not install:

```bash
curl -fsSL https://stable.repo.amd.com/rocm/gpg/packages.gpg \
  | gpg --dearmor | sudo tee /etc/apt/keyrings/amdrocm.gpg >/dev/null
sudo apt update
```

### `No matching distribution found for torch`

The `device-*` extra does not exist for your GPU architecture, or the version pin
is on the wrong package. The universal extra always works:

```bash
pip install --index-url https://stable.repo.amd.com/rocm/whl-next/ \
    'rocm[libraries,device-all]' 'torch[device-all]'
```

Note that the `==x.y.z` pin belongs on `rocm`, never on `torch` — ROCm's version
number is not PyTorch's.

### `Unsupported Ubuntu version`

Ubuntu 22.04 (`jammy`), 24.04 (`noble`) and 26.04 (`resolute`) are supported,
because ROCm 10.x is published for exactly those releases.

```bash
lsb_release -rs
```

Move to a supported release, or use the `Install_WSL_Ubuntu.bat` wizard.

---

## Launching and windows

### The desktop shortcut opens a window that closes instantly

A `.bat` created before v3.3.0 used malformed `wsl.exe` arguments. Delete it and
recreate it from **Desktop shortcut** in the menu.

If a newly created shortcut still misbehaves, check:

```powershell
wsl --list --verbose     # is your distro there and running?
wsl --update             # as Administrator
```

The shortcut uses `$WSL_DISTRO_NAME` to target your distro. Confirm it inside WSL:

```bash
echo "$WSL_DISTRO_NAME"
```

### "Port already in use"

Something is still holding the port — often a tool started from another terminal.

**Launch → Stop all AI servers and free VRAM** clears every port the toolkit knows
about. Or find the owner yourself:

```bash
ss -ltnp | grep 8188
```

### The tool starts, but the browser shows nothing

1. Confirm the tool printed its URL and is still running in its terminal.
2. Make sure you are opening it in your **Windows** browser: WSL2 forwards
   `localhost` automatically.
3. Some tools bind only to `127.0.0.1`. If you need access from elsewhere on your
   network, pass `--listen 0.0.0.0` with intent — that exposes the UI to your LAN.

---

## Speed

### The first generation is much slower than later ones

Expected: that is MIOpen searching for convolution algorithms. Both the toolkit's
`launch.sh` and the tuner persist the tuning database in
`~/.config/rocm-wsl-ai/miopen`, so this cost is paid once rather than on every
launch — but only for shapes already seen.

If the *first* generation is consistently brutal, run the tuner so the database is
pre-warmed for the shapes the benchmark exercises:

```bash
scripts/utils/perf_engine.py bench --save-report
```

### Everything is slow

1. **Is something else using the GPU?** A forgotten tool, a browser with hardware
   acceleration, a game. Check Windows Task Manager → Performance → GPU.
2. **Run the tuner** and read the verdict. If it says the defaults already won, the
   bottleneck is elsewhere — most often the model, resolution, or step count.
3. **Re-run the tuner after a driver or ROCm update.** A profile measured on an old
   driver may no longer be optimal; the preflight cache detects the change and the
   tuner re-measures.
4. **Do not stack tuning on top of tuning.** If you have added your own
   `PYTORCH_ALLOC_CONF`, `MIOPEN_*` or precision flags to `user.env`, remove them and
   let the engine measure.

### The tuner reports "inconclusive"

That is a feature. Either the candidates genuinely tie (the toolkit then applies
nothing rather than pretending), or the measurement was too noisy. Close other GPU
workloads and retry with the *thorough* mode.

---

## VRAM

### VRAM is not released after I close a tool

The process may still be running. **Launch → Stop all AI servers and free VRAM**
handles it, including forcing a stuck process.

### I want tools to stay running indefinitely

```bash
# ~/.config/rocm-wsl-ai/user.env
export SMART_SLEEP_DISABLE=1
```

Or set **Settings → Idle hibernation** to `0`. The default is 30 minutes.

### Hibernation and the wake page

After the idle timeout the server stops and a small page is served on the same port
so your browser gets a response instead of a connection error. Refreshing that page
restarts the real server. It reloads automatically once the tool is back up.

---

## Disk

### Out of space

ROCm and PyTorch together are large, and model checkpoints dwarf them.

```bash
du -sh ~/genai_env ~/ComfyUI ~/ComfyUI/models ~/.cache/pip 2>/dev/null
pip cache purge
```

WSL2 virtual disks do not shrink automatically when you delete files. To reclaim
space on the Windows side:

```powershell
wsl --shutdown
Optimize-VHD -Path "$env:LOCALAPPDATA\Packages\<distro>\LocalState\ext4.vhdx" -Mode Full
```

Or, on Windows 11 with the newer WSL, `wsl --manage <distro> --set-sparse true`.

---

## Updating

### The toolkit self-update fails

```bash
git -C ~/rocm-wsl-ai status
git -C ~/rocm-wsl-ai stash        # if you have local edits
git -C ~/rocm-wsl-ai pull --rebase --autostash
```

### A tool update broke something

The toolkit isolates tools from each other and never touches your models. Reinstall
the tool from **Install**; your settings, models and custom nodes live outside the
Python environment and are preserved.

### "Update All" replaced my ROCm PyTorch with a CUDA build

This used to happen when a tool's `requirements.txt` pinned `torch`, causing pip to
fetch the CUDA build from PyPI. The updater now strips every ROCm-managed package
from each requirements file before installing.

The list has to grow with ROCm, because the package names changed in 10.x. It now
covers `torch`, `torchvision`, `torchaudio`, `triton`, `triton-rocm`,
`triton_kernels`, `pytorch-triton*`, `rocm`, `rocm-sdk-*`, and the `amd-torch*`
/ `amd-torchvision*` device wheels. On 10.x a stray `triton` in a requirements file
is just as capable of replacing the ROCm build as `torch` itself.

If you already hit it, check and repair:

```bash
source ~/genai_env/bin/activate
python3 -c "import torch; print(torch.__version__, torch.version.hip)"
# expect: 2.14.0+rocm10.1.0... and a hip version, not None
```

If `torch.version.hip` is `None`, reinstall the base environment.

### The upgrade stopped and asks me to type `REMOVE`

That is the legacy teardown, and the prompt is deliberate. ROCm 10.x cannot be
installed alongside ROCm 7.2.x — both register `/opt/rocm` — so the old packages
have to go first. Nothing is deleted: `/opt/rocm-7.2.x` is renamed to
`*.retired-<timestamp>`, and the rollback is documented in
[UPGRADING.md](UPGRADING.md#rolling-back-to-72x).

If you would rather not, use `./upgrade.sh --target legacy` and stay on 7.2.x.

---

## ComfyUI-Manager and the toolkit's Python environment

ComfyUI-Manager installs Python packages into `~/genai_env` and may restart
ComfyUI to "reapply dependency installation". It is worth knowing how far that can
reach.

### Your environment is isolated, and that protects you

The toolkit builds `~/genai_env` as a virtual environment, and its `sys.path` is:

```text
/usr/lib/python310.zip
/usr/lib/python3.10
/usr/lib/python3.10/lib-dynload
/home/mauder/genai_env/lib/python3.10/site-packages
```

The user site-packages directory (`~/.local/lib/python3.10/site-packages`) is
**not** on that path, so packages installed with `pip3 --user` — including any
`nvidia-*` CUDA packages that may be present system-wide — are invisible to
ComfyUI and to torch. Verified on a real installation with 15 such packages
present: `pip list` inside the venv reported zero, and `import nvidia.cublas`
failed.

So a stray CUDA package elsewhere on the machine cannot contaminate the toolkit's
environment. That is by design.

### The one thing Manager *can* do

Manager resolves requirements with plain pip and does not know about the ROCm
constraints the toolkit applies. The guard the toolkit uses is stripping `torch`,
`torchvision`, `torchaudio` and `pytorch-triton-rocm` from every requirements file
before calling pip, because otherwise pip resolves `torch` from PyPI and downloads
the CUDA build. Manager does not do this.

Check after any Manager-driven dependency install:

```bash
source ~/genai_env/bin/activate
python3 -c "import torch; print(torch.__version__, torch.version.hip)"
# expect: 2.14.0+rocm10.1.0...  and a HIP version, never None
```

If `torch.version.hip` is `None`, or the version has no `+rocm`, the ROCm build has
been replaced. Restore it without rebuilding everything:

```bash
./menu.sh          # Updates -> Update one AI tool -> ComfyUI
```

That reinstalls ComfyUI's requirements *and* every custom node's requirements with
the ROCm guards applied.

### Cleaning up stray CUDA packages elsewhere

If `pip3 list` (outside the venv) shows `nvidia-*` packages you do not want, they
are inert for AMD work and safe to remove from the user site-packages:

```bash
pip3 uninstall -y $(pip3 list 2>/dev/null | awk '/^nvidia-/{print $1}')
```

This does not touch `~/genai_env`, and cannot affect torch: the venv has its own
copies of everything it needs.

---

## Upgrading

### What does the upgrade actually change?

```bash
./upgrade.sh --check
```

Changes nothing, and lists every component with its installed and available
version. See [`UPGRADING.md`](UPGRADING.md) for the full picture.

### The upgrade finished, but the GPU is not visible

Expected, and usually the last step. ROCm changed, and the DXCore bridge plus your
group membership are only re-established on a fresh WSL session:

```powershell
wsl --shutdown
```

Then reopen Ubuntu. If it persists after that, run **Settings → GPU Diagnostics**.

### The upgrade stopped partway

Safe to re-run. Each stage detects what is already done and skips it:

```bash
./upgrade.sh
```

The log from the last attempt:

```bash
ls -t ~/.config/rocm-wsl-ai/logs/upgrade-*.log | head -1
```

### "Could not find PyTorch wheels for ROCm X"

Usually no network. Version lookups are cached for 24 hours, so a run often
succeeds from cache. To retry with fresh data:

```bash
rm -rf ~/.config/rocm-wsl-ai/cache
./upgrade.sh --check
```

If AMD has published a ROCm release before its PyTorch wheels, the toolkit
deliberately installs the newest release that has both. That is reported in the
upgrade table rather than treated as an error.

### The new Python environment is broken

Your previous environment was moved aside rather than deleted:

```bash
ls -d ~/genai_env_backup_*
rm -rf ~/genai_env
mv ~/genai_env_backup_<timestamp> ~/genai_env
```

### A tool stopped working after the upgrade

Its dependencies were reinstalled against a new PyTorch, and something in its
tree may not be compatible yet. Reinstall that tool from **Install**, or pin it
back:

```bash
# ~/.config/rocm-wsl-ai/user.env
export COMFYUI_EXTRA_ARGS=""
```

Your models and custom nodes are outside the Python environment and unaffected.

### I want to undo a configuration migration

Every file the migration changed was backed up next to the original:

```bash
ls ~/.bashrc.pre-4.1.* ~/genai_env/bin/activate.pre-4.1.*
```

Each backup contains the file exactly as it was before. Note that restoring
`PYTORCH_HIP_ALLOC_CONF` will bring back the segfault it caused.

### An upgrade is offered but I do not want it

Nothing happens automatically — the toolkit only ever reports that an upgrade is
available. To keep a pinned ROCm, skip the ROCm stages:

```bash
./upgrade.sh --rocm-only      # toolkit only, leaves ROCm alone
```

---

## Still stuck?

Run the full diagnostics and include the output in your report:

```bash
scripts/utils/gpu_diag.sh
scripts/utils/perf_engine.py probe
scripts/utils/perf_engine.py doctor
```

Then open an issue with the template — it asks for exactly these blocks. Please
**redact your username and any paths you would rather not share**.
