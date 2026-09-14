<div align="center">

# ROCm WSL2 AI Toolkit

**Run Stable Diffusion, ComfyUI and local LLMs on an AMD Radeon GPU — fast, and without the setup pain.**

[![CI](https://github.com/daMustermann/rocm-wsl-ai/actions/workflows/ci.yml/badge.svg)](https://github.com/daMustermann/rocm-wsl-ai/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-4.1.0-blue.svg)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Platform: WSL2](https://img.shields.io/badge/platform-WSL2-0078D4.svg)](#requirements)
[![ROCm latest](https://img.shields.io/badge/ROCm-latest%20auto--detected-ED1C24.svg)](docs/UPGRADING.md)
[![PyTorch ROCm](https://img.shields.io/badge/PyTorch-rocm-EE4C2C.svg)](https://pytorch.org/)
[![Python 3.10+](https://img.shields.io/badge/python-3.10%2B-3776AB.svg)](https://www.python.org/)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

<img src="docs/assets/preview.png" alt="ROCm WSL2 AI Toolkit menu" width="820">

</div>

---

> ### ⬆️ Already using an older version? One command:
>
> ```bash
> cd ~/rocm-wsl-ai && ./upgrade.sh
> ```
>
> Updates the toolkit, upgrades ROCm to the newest release, rebuilds PyTorch,
> repairs settings older versions left harmful, and re-tunes performance.
> Your models and custom nodes are never touched.
>
> Not sure? `./upgrade.sh --check` changes nothing and tells you what would happen.
> Full details in **[docs/UPGRADING.md](docs/UPGRADING.md)**.

---

## Why this exists

Running AI on an AMD card under Windows is genuinely unpleasant:

| The problem | What this toolkit does |
|---|---|
| Native Windows ROCm support lags Linux and is often unstable | Runs everything in **WSL2**, which is dramatically faster and more reliable |
| WSL2 needs a GPU bridge, exact driver versions, and matching wheels | Installs **ROCm + ROCDXG + PyTorch** end to end, in one menu choice |
| Every ROCm release invalidates a hand-written installer | **Resolves the newest release from AMD's repositories at run time** — no pinned versions to rot |
| `HSA_OVERRIDE_GFX_VERSION`, `PYTORCH_ROCM_ARCH`, MIOpen caches — endless env var archaeology | Detects your GPU and configures all of it automatically |
| "PyTorch can't see my GPU" with no useful error | A cached preflight that tells you *which* of the five usual causes applies |
| Upgrading means reinstalling everything by hand | **One command** updates the toolkit, ROCm, PyTorch, your tools, and repairs old settings |
| A forgotten terminal holds 24 GB of VRAM hostage, wrecking your games | Idle hibernation frees **100% of VRAM** back to Windows; a browser refresh wakes it |
| Launch flags copied from a 2023 blog post make a 24 GB card behave like an 8 GB one | A tuner that **measures your actual GPU** and derives the flags from the result |

---

## Measured, not guessed

Most "optimised for AMD" guides are folklore. This toolkit's tuner runs real
diffusion-shaped work — grouped convolutions, attention, and a multi-step
denoising loop — on your hardware, then keeps the configuration that actually won.

Real output from an **RX 7900 XTX (gfx1100, 24 GB)** running WSL2 + ROCm 7.2.3:

```
profile                     score  vs stock  cold start     step  status
----------------------------------------------------------------------
ComfyUI default VRAM       127.95     +0.0%     2213 ms  17.0 ms  ok
Resident models            130.24     +1.8%     2262 ms  16.9 ms  ok
Resident + MIOpen fast      60.36    -52.8%     1025 ms   8.9 ms  ok
Resident + 1GB headroom     56.97    -55.5%      955 ms   9.0 ms  WINNER
MIOpen cache fast-path      60.29    -52.9%     1048 ms   7.7 ms  ok
Aggressive residency        61.30    -52.1%     1045 ms   8.8 ms  ok
Lean VRAM (chunked)        125.31     -2.1%     2182 ms  16.0 ms  ok
----------------------------------------------------------------------
drift check: reference configuration varied 5% across the run (tolerance 25%)
```

**Cold start** is the wait before your first image; **step** is per denoising step.
Both roughly halve. The clearest evidence that the old flags were hurting: `--lowvram`,
which the toolkit used to force on everyone, is the slowest row in the table.

Three things this tuner does that matter more than the numbers:

- **It refuses to invent wins.** If the best candidate is within measurement noise of
  the defaults, it says so and applies nothing. When several profiles tie, it picks
  the *safest* one rather than whichever sampled 1% faster. It also detects GPU
  drift during a run and throws the whole result away rather than reporting it.
- **It caught real bugs in this toolkit.** Building it surfaced that
  `PYTORCH_HIP_ALLOC_CONF` **segfaults** PyTorch 2.9.1+rocm7.2.3 on import — a
  variable the previous version actively migrated users toward — that the old
  auto-tuner was tuning two environment variables which do not affect PyTorch's HIP
  backend at all, and three separate ways its own first version was measuring the
  wrong thing. See [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md).

---

## Quick start

### Windows one-time prerequisites

| Requirement | Why |
|---|---|
| **Windows 11** with WSL2 | The whole toolkit targets WSL2 |
| **AMD Adrenalin 26.2.2 or newer** | Exposes the DXCore GPU bridge to WSL |
| **Windows SDK** | Needed to build `librocdxg`, the WSL GPU bridge |

> Missing either of the last two is the most common cause of a failed install.
> Let the toolkit check for you: **Settings → GPU diagnostics**.

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/daMustermann/rocm-wsl-ai/main/install.sh | bash
```

Prefer to read what you run first? That is entirely reasonable:

```bash
git clone https://github.com/daMustermann/rocm-wsl-ai.git
cd rocm-wsl-ai
./install.sh
```

Don't have WSL2 or Ubuntu yet? Right-click **`Install_WSL_Ubuntu.bat`** and choose
*Run as administrator*. It installs WSL2 and Ubuntu 24.04 for you.

### Then

Pick **Quick start** in the menu. It works out what your machine is missing and
does it in order: base environment → (you restart WSL) → first tool → tuning.

> **The WSL restart is not optional.** Run `wsl --shutdown` in PowerShell after the
> base install. That is what applies your group membership and activates the
> DXCore bridge — without it, PyTorch cannot see your GPU.

---

## Upgrading

```bash
cd ~/rocm-wsl-ai && ./upgrade.sh
```

One command that brings an older installation fully up to date:

- updates the toolkit and **restarts itself with the new code**
- upgrades **ROCm** to the newest release AMD publishes for your Ubuntu version
- rebuilds the **ROCDXG** WSL GPU bridge from the newest tag
- rebuilds `~/genai_env` with the matching **PyTorch** wheels
- **migrates settings that older versions left behind** — including
  `PYTORCH_HIP_ALLOC_CONF`, which segfaults current PyTorch, and a stale
  `HSA_OVERRIDE_GFX_VERSION`, which hides your GPU entirely
- reinstalls your tools' dependencies and **re-measures performance**

Every file it changes is backed up, the migration is idempotent, and the previous
Python environment is moved aside rather than deleted. Models, custom nodes,
extensions and datasets are never touched.

```bash
./upgrade.sh --check    # what would change? (changes nothing)
./upgrade.sh --yes      # unattended
```

Full guide, including troubleshooting and version-specific notes:
**[docs/UPGRADING.md](docs/UPGRADING.md)**

### ROCm versions are discovered, not pinned

Older releases hardcoded wheel filenames like
`torch-2.9.1+rocm7.2.3.lw.gitebc02d69-cp310-cp310-linux_x86_64.whl`. That hash
changes with every ROCm patch, so a new AMD release broke the installer until
someone edited it by hand.

The toolkit now reads AMD's repository index at run time and picks the newest
release that has an apt repository for your Ubuntu version **and** PyTorch wheels
for your Python version. New ROCm releases therefore work without a toolkit
update — `./upgrade.sh --check` will offer them as soon as AMD publishes them.
Offline machines fall back to a known-good version.

---

## What you get

### Performance engine

```bash
scripts/utils/perf_engine.py probe      # what does this machine actually support?
scripts/utils/perf_engine.py bench      # measure candidates, apply the winner
scripts/utils/perf_engine.py show       # what tuning is active right now
scripts/utils/perf_engine.py doctor     # self-check, no GPU required
```

It tunes only levers that measurably change GPU behaviour, and reports the ones
that turned out to be noise instead of pretending otherwise.

### Unified launcher

Every tool launches through `lib/launch.sh`, which:

- Sets the GPU environment **before Python starts** (the single most common cause
  of a silently invisible GPU — see below).
- Applies your tuned profile, validating each ComfyUI flag against the installed
  version's real `--help` output, so a flag from a newer release can't break launch.
- Caches the GPU preflight: **~4 ms** warm instead of a full `import torch` on
  every launch.
- Hibernates after 30 minutes idle and gives **all** VRAM back to Windows.

### Any tool you want

The toolkit ships ComfyUI, SD.Next, Automatic1111, kohya_ss and Text Generation
WebUI — and it can manage **any** git repository as a first-class tool. Point it at
a repo (GitHub, Codeberg, self-hosted), give it a start command, and it gets cloned,
installed, launched, updated and added to your Windows desktop like a built-in.

**Install → Add a third-party tool**, or see [`docs/ADDING_TOOLS.md`](docs/ADDING_TOOLS.md).

> The built-in registry deliberately does not list face-swap or
> likeness-manipulation applications, even though the generic mechanism runs them
> fine. GitHub's Acceptable Use Policies prohibit non-consensual intimate imagery
> and synthetic media intended to mislead, and repositories shipping installers for
> named face-swap apps get taken down regardless of the tool's legality. The
> registry is generic precisely so the toolkit stays useful without putting the
> project — or you — in that position.

---

## The GPU-visibility trap

Worth stating plainly, because it explains a large share of "AMD ROCm doesn't work"
reports. On this exact stack:

```text
$ python3 -c "import torch; print(torch.cuda.is_available())"
False                                    # no HSA_ENABLE_DXG_DETECTION

$ HSA_ENABLE_DXG_DETECTION=1 python3 -c "import torch; print(torch.cuda.is_available())"
True                                     # GPU present
```

`rocminfo` reports your GPU either way, so every diagnostic says the hardware is
fine while PyTorch sees nothing. The previous version of this toolkit appended the
variable to the virtualenv's `activate` script — so the GPU appeared only if you
remembered to activate that venv first, and vanished in a fresh shell, from an IDE,
or from a script.

The launcher now exports the full GPU environment before anything else runs, and
`perf_engine.py doctor` verifies that PyTorch can actually boot under a real
profile environment.

---

## Requirements

- **GPU**: AMD Radeon RX 7000 series (RDNA3), RX 9000 series (RDNA4), or Ryzen
  Strix / Strix Halo APUs — `gfx1100` and newer
- **OS**: Windows 11 + WSL2 with Ubuntu 22.04 or 24.04
- **Windows driver**: AMD Adrenalin 26.2.2 or newer
- **Windows SDK**: required to build the ROCDXG bridge
- **Disk**: ~20 GB free (ROCm and PyTorch are large)
- **Python**: 3.10 (Ubuntu 22.04) or 3.12 (Ubuntu 24.04) — handled automatically

RDNA2 and older (`gfx1030` and below) are **not supported**: AMD does not ship the
required ROCm components for WSL2 on those architectures.

---

## What gets installed

| Component | Version |
|---|---|
| **ROCm** | The newest release AMD publishes with wheels for your Python — resolved at run time |
| **ROCDXG** (`librocdxg`) | The newest release tag, built from source |
| **PyTorch** | The newest AMD ROCm wheel matching your ROCm and Python version |
| **Triton** | The matching AMD build |
| **Python env** | Isolated in `~/genai_env`, so nothing touches system Python |

There is no pinned version to go stale. Run `./upgrade.sh --check` to see exactly
which versions are current and which are available for your machine.

### Optional tools

| Tool | What it is | Default port | Environment |
|---|---|---|---|
| ComfyUI | Node-based diffusion workflows | 8188 | `~/genai_env` |
| SD.Next | Feature-rich Stable Diffusion WebUI | 7860 | own |
| Automatic1111 | The original Stable Diffusion WebUI | 7860 | own |
| kohya_ss | LoRA / DreamBooth training | 7861 | `~/kohya_env` |
| Text Generation WebUI | Local LLM chat | 5000 | `~/genai_env` |
| *anything else* | Any git repository you register | — | your choice |

---

## Documentation

| Document | Contents |
|---|---|
| [`docs/UPGRADING.md`](docs/UPGRADING.md) | **Upgrading from an older version — start here if you already use this toolkit** |
| [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) | What the tuner measures, which levers are real, and which are folklore |
| [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) | Symptom-first fixes for the failures people actually hit |
| [`docs/ADDING_TOOLS.md`](docs/ADDING_TOOLS.md) | Registering your own tools and writing start scripts |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | How the libraries, engine and menu fit together |
| [`docs/WSL2_SETUP_GUIDE.md`](docs/WSL2_SETUP_GUIDE.md) | Manual WSL2 setup, for when you want to understand the plumbing |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed, version by version |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Development setup and how to help |

---

## Command reference

| Command | Purpose |
|---|---|
| `./menu.sh` | Interactive menu — start here |
| `./upgrade.sh` | **Upgrade everything automatically** (`--check`, `--yes`, `--force`) |
| `./install.sh` | One-line installer; detects an existing install and upgrades it |
| `scripts/utils/perf_engine.py <cmd>` | `probe` · `profiles` · `bench` · `apply` · `show` · `doctor` |
| `scripts/utils/gpu_diag.sh` | Full GPU/ROCm health check |
| `scripts/utils/smart_update.sh` | Scan installed tools, update what is out of date |
| `scripts/start/comfyui.sh` | Launch ComfyUI directly (same for the other tools) |

### Where your settings live

Everything is under `~/.config/rocm-wsl-ai/` and nothing else is touched:

```text
user.env            your settings — ports, idle timeout, GPU overrides
perf.env            the applied tuning profile (generated)
perf_profile.json   full tuning result and provenance (generated)
tools.local         your third-party tools (generated)
miopen/             persistent convolution tuning database
logs/               launcher logs
```

---

## Troubleshooting quick index

| Symptom | First thing to try |
|---|---|
| `torch.cuda.is_available()` is `False` | `wsl --shutdown` in PowerShell, then reopen Ubuntu |
| ComfyUI window closes instantly | Recreate the desktop shortcut from the menu |
| First image takes forever, then it's fast | Normal once; run the tuner to cut it further |
| VRAM not released after closing a tool | **Launch → Stop all AI servers and free VRAM** |
| Everything is slow | Check nothing else is using the GPU, then re-run the tuner |
| Install fails at the ROCDXG step | Windows SDK is missing — see Settings → GPU diagnostics |

Full details in [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

---

## Roadmap

- [ ] In-app model browser so the first checkpoint can be downloaded from the menu
- [ ] Per-model VRAM presets (SD1.5 / SDXL / Flux fit differently on the same card)
- [ ] Bake the tuned MIOpen database into first-run so the first generation is fast immediately
- [ ] Automatic report sharing for the tuner, so users can compare across GPUs

---

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

This toolkit automates and glues together other people's excellent work:

- **AMD** — [ROCm](https://www.amd.com/en/products/software/rocm.html) and the
  [librocdxg](https://github.com/ROCm/librocdxg) WSL bridge
- **The PyTorch team** — ROCm integration and the SDPA attention kernels
- **[ComfyUI](https://github.com/comfyanonymous/ComfyUI)** · **[SD.Next](https://github.com/vladmandic/sdnext)** ·
  **[Automatic1111](https://github.com/AUTOMATIC1111/stable-diffusion-webui)** ·
  **[kohya_ss](https://github.com/bmaltais/kohya_ss)** ·
  **[Text Generation WebUI](https://github.com/oobabooga/text-generation-webui)** — the tools themselves
- **[Charm](https://charm.sh)** — `gum`, which makes the terminal UI pleasant

Each bundled tool is a separate project with its own licence and maintainers; the
toolkit only installs and configures them.
