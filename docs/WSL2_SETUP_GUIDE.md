# WSL2 Setup Guide for ROCm AI Toolkit

The plumbing-level version of the install: what each step does, and how to do it
by hand if you would rather not use the toolkit.

**Most people should just run the installer.** It discovers versions, picks the
right package for your GPU, and rebuilds PyTorch correctly:

```bash
curl -fsSL https://raw.githubusercontent.com/daMustermann/rocm-wsl-ai/main/install.sh | bash
```

This guide exists for when that does not work, when you want to understand what
is being installed, or when you are on a machine the installer will not touch.

---

## Table of contents

1. [Prerequisites](#prerequisites)
2. [WSL2 installation](#wsl2-installation)
3. [Ubuntu installation](#ubuntu-installation)
4. [AMD driver installation](#amd-driver-installation)
5. [ROCm installation](#rocm-installation)
6. [PyTorch installation](#pytorch-installation)
7. [Verifying](#verifying)
8. [Optional: kohya_ss](#optional-kohya_ss-training)
9. [Windows desktop shortcuts](#windows-desktop-shortcuts)
10. [Staying on ROCm 7.2.x](#staying-on-rocm-72x)
11. [Troubleshooting](#troubleshooting)
12. [Performance tips](#performance-tips)
13. [Quick reference](#quick-reference)

---

## Prerequisites

### Windows

| Requirement | Notes |
|---|---|
| **Windows 11** | Required. Windows 10 is not supported by ROCm 10.x |
| **AMD Adrenalin 26.10.41.05+** | The *for WSL2* driver package. This is the single most common cause of failure |
| **WSL2** | `wsl --install` from PowerShell |

There is **no Windows SDK requirement.** ROCm 7.2.x needed one because the WSL GPU
bridge had to be compiled from source; ROCm 10.x ships that bridge itself.

Two Windows features interfere with ROCm and should be off:

- **Windows Defender Application Guard (WDAG)** — Control Panel → Programs →
  Programs and Features → Turn Windows features on or off → clear it.
- **Smart App Control (SAC)** — Settings → Privacy & security → Windows Security →
  App & browser control → Off.

### Check your Windows version

```powershell
# PowerShell
[System.Environment]::OSVersion.Version
winver
```

### Check the AMD driver version

```powershell
Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion
```

ROCm 10.x needs a driver at or above **26.10.41.05**, which ships as Windows
driver version `32.0.31041.3013` or newer.

> If you are upgrading an existing installation, read
> [UPGRADING.md](UPGRADING.md) first. ROCm 10.x cannot be installed alongside
> ROCm 7.2.x, and the transition removes your old packages.

---

## WSL2 installation

### Enable WSL2

From PowerShell (Administrator):

```powershell
wsl --install --no-distribution
```

### Restart

This one is not optional. Reboot Windows.

### Check

```powershell
wsl --status
wsl --list --verbose
```

### Update WSL

```powershell
wsl --update
```

---

## Ubuntu installation

ROCm 10.x is published for Ubuntu 22.04, 24.04 and 26.04. AMD publishes them
under `ubuntu2204` / `ubuntu2404` / `ubuntu2604` paths, which is why the toolkit
maps your codename (`jammy` / `noble` / `resolute`) rather than guessing.

| Ubuntu | Default Python | PyTorch wheels |
|---|---|---|
| 26.04 (`resolute`) | 3.13 | `cp313` |
| 24.04 (`noble`) | 3.12 | `cp312` |
| 22.04 (`jammy`) | 3.10 | `cp310` |

ROCm 10.1 ships wheels for CPython 3.10 through 3.14, so all three resolve.

```powershell
wsl --install -d Ubuntu-24.04
```

Set the default if you have more than one:

```powershell
wsl --set-default Ubuntu-24.04
```

On first launch, create your user and password.

---

## AMD driver installation

Download **AMD Software: Adrenalin Edition for WSL2**, version **26.10.41.05**
or newer:

<https://www.amd.com/en/resources/support-articles/release-notes/RN-RAD-ROCM-10-01.html>

Install it on Windows, then reboot. WSL picks it up automatically — there is no
in-distro driver to install, because WSL uses the Windows driver through DXCore.

Verify:

```bash
ls -l /dev/dxg
```

A character device owned by root, mode `crw-rw-rw-`. **If this is missing,
nothing else will work** — no ROCm install can make a GPU appear. Close every WSL
window and run `wsl --shutdown` from PowerShell.

---

## ROCm installation

### Automated (recommended)

```bash
./menu.sh
# Select: Install → Base environment
```

### Manual

#### Step 1: Update the system

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y wget curl gpg ca-certificates
```

#### Step 2: Identify your GPU architecture

ROCm 10.x publishes one package per GPU architecture, and PyTorch needs a
matching `device-*` extra. Get this wrong and you get a machine with no working
GPU and no obvious reason why.

| Your GPU | Target |
|---|---|
| RX 7900 XTX / 7900 XT / 7900 GRE / PRO W7900 / W7800 | `gfx1100` |
| RX 7800 XT / 7700 XT / 7700 / PRO W7700 | `gfx1101` |
| RX 7600 | `gfx1102` |
| RX 9070 / 9070 XT / AI PRO R9700 / R9600 | `gfx1201` |
| RX 9060 / 9060 XT | `gfx1200` |
| PRO W6800 / V620 | `gfx1030` |

Full table: <https://rocm.docs.amd.com/en/latest/reference/gpu-arch-specs.html>

To read it off the hardware:

```bash
lspci | grep -iE 'vga|3d'
```

#### Step 3: Add AMD's repository

ROCm 10.x uses a deb822 source and a keyring, not the older one-line `deb`
entry:

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://stable.repo.amd.com/rocm/gpg/packages.gpg \
  | gpg --dearmor | sudo tee /etc/apt/keyrings/amdrocm.gpg >/dev/null

sudo tee /etc/apt/sources.list.d/amdrocm-stable.sources << 'EOF'
X-Repo-Id: amdrocm-stable
Types: deb
URIs: https://stable.repo.amd.com/rocm/core/packages/ubuntu2404/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/amdrocm.gpg
Enabled: yes
EOF

sudo apt update
```

Change `ubuntu2404` to `ubuntu2204` or `ubuntu2604` to match your release.

#### Step 4: Install ROCm

Install the package for **your** architecture. It is a fraction of the size of
the all-architecture package and avoids pulling kernels for hardware you do not
have:

```bash
# Substitute your own target from the table above.
sudo apt install -y amdrocm10.1-gfx1100
```

That is the whole install. There is nothing to compile — ROCm 10.x ships the WSL
GPU bridge (`librocdxg`) inside its own artifacts:

```bash
ls /opt/rocm/core-*/lib/librocdxg.so
```

#### Step 5: Grant GPU access

```bash
sudo usermod -a -G render,video "$LOGNAME"
```

Then restart WSL, or the group change will not apply:

```powershell
wsl --shutdown
```

---

## PyTorch installation

### Through the toolkit (recommended)

The base environment install includes PyTorch, resolved against your Python and
GPU at run time.

### Manual

#### Step 1: Create a virtual environment

Use the Python that matches your Ubuntu release:

```bash
python3 -m venv ~/genai_env
source ~/genai_env/bin/activate
pip install --upgrade pip wheel
```

#### Step 2: Install from AMD's index

PyTorch is no longer downloaded as named wheel files. AMD publishes a wheel index
and the GPU-specific kernels are selected with a `device-*` extra, so `pip`
resolves the whole dependency set:

```bash
pip install --index-url https://stable.repo.amd.com/rocm/whl-next/ \
    'rocm[libraries,device-gfx1100]==10.1.0' \
    'torch[device-gfx1100]' \
    'torchvision[device-gfx1100]' \
    'torchaudio'
```

Notes that matter:

- The `==10.1.0` pin belongs on **`rocm`** only. `torch==10.1.0` would ask for a
  PyTorch release that does not exist — 10.1.0 is the ROCm version, not torch's.
- `device-gfx1100` must match the apt package you installed. If you are unsure,
  `device-all` works and is larger.
- If your GPU architecture has no `device-*` extra, the install fails with
  `No matching distribution`. Use `device-all`.

#### Step 3: Optional extras

```bash
pip install sageattention        # optional attention kernels
```

#### Step 4: Make the GPU environment available

```bash
export HSA_ENABLE_DXG_DETECTION=1
```

ROCm 10.x detects WSL automatically and this defaults to 1, so the export is a
belt-and-braces measure for older 7.2.x stacks.

**Do not set `HSA_OVERRIDE_GFX_VERSION` under WSL.** It is not a fallback. DXCore
enumerates the GPU itself, and an override makes the runtime reject the device —
PyTorch then reports no GPU while `rocminfo` still lists one, which is a far more
confusing problem than the one it claims to solve.

---

## Verifying

### ROCm

```bash
rocminfo | grep -i wsl
# WSL environment detected.
```

That line is the confirmation that the bridge loaded. Without it, PyTorch will
not see a GPU no matter what else you do.

### PyTorch

```bash
~/genai_env/bin/python -c "
import torch
print('version', torch.__version__)
print('hip    ', torch.version.hip)
print('gpu    ', torch.cuda.is_available())
print('device ', torch.cuda.get_device_name(0) if torch.cuda.is_available() else '-')
"
```

Expected:

```text
version 2.14.0+rocm10.1.0
hip     7.16.26385
gpu     True
device  AMD Radeon RX 7900 XTX
```

### Telemetry

ROCm 10.1 gives WSL access to GPU telemetry for the first time, via `amd-smi`:

```bash
amd-smi static
amd-smi metric
```

`amd-smi event` is **not** supported under WSL and may hang — do not run it.
Per-process GPU usage is also unavailable there.

### The whole thing at once

```bash
./scripts/utils/gpu_diag.sh
```

---

## Optional: kohya_ss training

[kohya_ss](https://github.com/bmaltais/kohya_ss) is a web GUI for LoRA training
and fine-tuning.

```bash
./menu.sh
# Select: Install → kohya_ss
```

| Item | Location |
|---|---|
| Repository | `~/kohya_ss` |
| Dedicated venv | `~/kohya_env` |
| Web GUI | http://localhost:7861 |

> kohya_ss gets its **own** virtual environment on purpose. Its training
> dependencies conflict with the inference tools in `~/genai_env`, and sharing one
> environment reliably breaks one or the other.

---

## Windows desktop shortcuts

```bash
./menu.sh
# Select: Create Desktop shortcuts
```

Each shortcut is a `.bat` file on your Windows Desktop that calls
`wsl.exe -d <distro> -- bash -l "<launcher>"`.

**Shortcut does nothing when double-clicked:** the file is missing CRLF line
endings. Run **Settings → Edit settings → (re)create shortcuts**, or from WSL:

```bash
cd ~/rocm-wsl-ai && ./scripts/utils/create_shortcut.sh comfyui
```

---

## Staying on ROCm 7.2.x

ROCm 10.x ships WSL support as a **technical preview**. If it misbehaves on your
machine, stay on 7.2.x — it is still supported.

```bash
./upgrade.sh --target legacy
```

### How the 7.2.x install differs

Everything below is only needed on the legacy channel.

**The package is `rocm`, not `amdrocm10.1-*`**, from AMD's older repository:

```bash
wget https://repo.radeon.com/rocm/rocm.gpg.key \
  | gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg >/dev/null

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2.4 $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/rocm.list >/dev/null

sudo apt update
sudo apt install -y python3-setuptools python3-wheel
sudo apt install -y rocm
```

**The WSL GPU bridge has to be compiled**, because ROCm 7.2.x does not ship it.
This is the step that needs the Windows SDK:

```bash
sudo apt install -y cmake gcc

git clone https://github.com/ROCm/librocdxg.git
cd librocdxg

export win_kits="/mnt/c/Program Files (x86)/Windows Kits/10/Include"
export sdk_ver=$(ls -1 "$win_kits" | grep -E '^10\.' | sort -V | tail -1)
export win_sdk="${win_kits}/${sdk_ver}"

mkdir -p build && cd build
cmake .. -DWIN_SDK="${win_sdk}/shared"
make
sudo make install
```

Alternatively, download the prebuilt package from the
[librocdxg releases page](https://github.com/ROCm/librocdxg/releases):

```bash
sudo dpkg -i rocdxg-roct_<version>_amd64.deb
```

**PyTorch wheels are named files** on this channel, and must match your Python:

```bash
python3 -m venv ~/genai_env
source ~/genai_env/bin/activate

# Example for ROCm 7.2.4 / Python 3.10. Substitute your own release.
cd /tmp
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.4/torch-2.10.0%2Brocm7.2.4-cp310-cp310-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.4/torchvision-0.25.0%2Brocm7.2.4-cp310-cp310-linux_x86_64.whl
wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.4/torchaudio-2.10.0%2Brocm7.2.4-cp310-cp310-linux_x86_64.whl
pip3 install torch-*.whl torchvision-*.whl torchaudio-*.whl
```

Those filenames embed a git hash that changes with every patch release, which is
exactly the fragility that 5.0 removes. Browse
<https://repo.radeon.com/rocm/manylinux/> to find the current ones, or use the
toolkit, which resolves them for you.

**`HSA_ENABLE_DXG_DETECTION=1` is mandatory** on this channel — ROCr only learned
to auto-detect WSL in 7.13.

---

## Troubleshooting

### `/dev/dxg` is missing

The single most important thing to check. Without it WSL cannot reach the GPU.

```bash
ls -l /dev/dxg
```

If absent: `wsl --shutdown` from PowerShell, reopen, check again. If it persists,
your Windows driver is not exposing DXCore — install the Adrenalin *for WSL2*
package at 26.10.41.05 or newer.

### `rocminfo` shows no GPU

1. `ls -l /dev/dxg` — see above.
2. Confirm the driver: `amd-smi version` should report ROCm 10.1.0.
3. Confirm the bridge: `ls /opt/rocm/core-*/lib/librocdxg.so`.
4. `wsl --shutdown`, reopen.

### `torch.cuda.is_available()` is `False`

1. `rocminfo | grep -i wsl` — must say `WSL environment detected.`
2. Check you are using the right interpreter:
   `which python` should be `~/genai_env/bin/python`.
3. Check `HSA_OVERRIDE_GFX_VERSION` is **unset**. If it is set, the runtime is
   rejecting your device — that is the bug, not the fix:
   ```bash
   echo "${HSA_OVERRIDE_GFX_VERSION:-<unset>}"
   sed -i '/HSA_OVERRIDE_GFX_VERSION/d' ~/.config/rocm-wsl-ai/user.env
   sed -i '/HSA_OVERRIDE_GFX_VERSION/d' ~/.bashrc
   ```
4. Just installed? `wsl --shutdown` first — this is normal and expected.

### `No matching distribution found for torch`

The `device-*` extra does not exist for your architecture. Use the universal one:

```bash
pip install --index-url https://stable.repo.amd.com/rocm/whl-next/ \
    'rocm[libraries,device-all]' 'torch[device-all]'
```

Then check what the apt package was scoped to, and reinstall the matching one.

### `ImportError: libhsa-runtime64.so`

Some torch builds bundle an HSA runtime that conflicts with the one ROCm
provides. Only if the GPU is invisible *and* the bundled copy exists:

```bash
location=$(pip show torch | awk -F ': ' '/^Location/{print $2}')
rm -f "$location"/torch/lib/libhsa-runtime64.so*
```

### A workload hangs on a device-side assertion

Known ROCm 10.1 WSL issue: certain device-side executions can leave the GPU
workload stopped while the host process waits for completion. Most HIP and OpenCL
workloads are unaffected. Terminate the process and restart the application.

### Permission denied

```bash
sudo usermod -a -G render,video "$USER"
```

Then `wsl --shutdown`. Note that under WSL this is less often the cause than on
native Linux, because access is brokered by DXCore.

### Slow performance

1. Keep your tools and models inside the WSL filesystem (`/home/...`), not
   `/mnt/c/...`. Crossing the 9p boundary is dramatically slower.
2. Give WSL more resources — `%UserProfile%\.wslconfig`:
   ```ini
   [wsl2]
   memory=24GB
   processors=12
   swap=8GB
   ```
3. Run the tuner: **Performance → Auto-tune**. It measures on your GPU rather than
   applying folklore.

### Valgrind hangs

Known ROCm 10.1 WSL issue: WSL reserves GPU address space up front, which can
collide with Valgrind's reserved range when system RAM is large. Limit WSL's
memory in `.wslconfig` to below ~36 GB if you need Valgrind.

---

## Performance tips

- **Tune, do not guess.** `./menu.sh → Performance → Auto-tune` measures four
  shaped workloads on your GPU. See [PERFORMANCE.md](PERFORMANCE.md).
- **Keep files in the Linux filesystem.** `/mnt/c` is a network mount.
- **Leave headroom in `.wslconfig`.** AMD documents a Valgrind collision above
  roughly 36 GB.
- **The idle timer is worth enabling.** **Settings → Idle hibernation** stops a
  forgotten server and releases its VRAM.

---

## Quick reference

```bash
wsl --shutdown                              # from PowerShell — restarts WSL
wsl --update                                # from PowerShell

ls -l /dev/dxg                              # the GPU must be reachable here
rocminfo | grep -i wsl                      # "WSL environment detected."
amd-smi version                             # ROCm + driver versions
amd-smi metric                              # live telemetry (works under WSL)

source ~/genai_env/bin/activate             # use the ROCm PyTorch
python -c "import torch; print(torch.cuda.is_available())"

./menu.sh                                   # the toolkit
./upgrade.sh --check                        # what would change
./scripts/utils/gpu_diag.sh                 # full health check
./scripts/utils/perf_engine.py bench        # measure this GPU
```

---

## Getting help

1. Run the diagnostics and paste the output — it answers most questions:
   ```bash
   ./scripts/utils/gpu_diag.sh
   ```
2. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
3. Open an issue with the diagnostics output attached.

## Resources

- [ROCm 10.1 documentation](https://rocm.docs.amd.com/en/docs-10.1.0/)
- [Installing ROCm on WSL](https://rocm.docs.amd.com/en/docs-10.1.0/install/rocm.html)
- [GPU architecture specs](https://rocm.docs.amd.com/en/latest/reference/gpu-arch-specs.html)
- [AMD SMI under WSL](https://rocm.docs.amd.com/projects/amdsmi/en/docs-10.1.0/how-to/amdsmi-wsl-mode.html)
- [TheRock build system](https://github.com/ROCm/TheRock)
- [WSL installation (Microsoft)](https://learn.microsoft.com/en-us/windows/wsl/install)