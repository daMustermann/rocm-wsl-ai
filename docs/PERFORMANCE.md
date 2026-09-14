# Performance on AMD GPUs

This document explains what the toolkit actually tunes, what it deliberately does
**not** tune, and how to verify any claim it makes. Every number here was measured
on real hardware with `scripts/utils/perf_engine.py` — nothing is copied from a blog
post.

Reference machine: **AMD Radeon RX 7900 XTX** (`gfx1100`, 24 GB), WSL2 Ubuntu 22.04,
ROCm 7.2.3, PyTorch 2.9.1+rocm7.2.3, 48 CUs.

---

## The short version

| Change | Effect | Confidence |
|---|---|---|
| MIOpen `FIND_MODE=FAST` with a persistent cache | First convolution **2213 ms → 955 ms**; denoise step **17.0 ms → 9.0 ms** | Measured, reproducible |
| Stop forcing `--lowvram` on capable cards | Removes ComfyUI's per-block weight streaming | Verified from ComfyUI's own log output |
| Prefer the fastest attention kernel | 4.7× between `MATH` and fused kernels | Measured; the dispatcher already picks well |
| Allocator / pinned-memory tuning | No measurable effect | Measured, so **not** applied |
| `MIGRAPHX_MLIR_USE_SPECIFIC_OPS` | Nothing — PyTorch does not use MIGRAPHX | Removed from the toolkit |

A full tuned run on the reference machine:

```text
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
```

Roughly halving both the time to first image and the per-step time. `--lowvram`
being the *worst* performer is the clearest evidence that the old hardcoded flags
were costing real performance.

---

## How the tuner works

```bash
scripts/utils/perf_engine.py probe    # capabilities of this machine
scripts/utils/perf_engine.py bench    # measure candidates, pick a winner
scripts/utils/perf_engine.py show     # what is applied right now
scripts/utils/perf_engine.py doctor   # self-check, no GPU needed
```

### The workload

A tune that only times `matmul` measures the wrong thing. Diffusion inference is
dominated by grouped convolutions, attention and normalisation, and the cost that
users actually notice is the *first* generation after launching a tool. So each
candidate is measured with:

1. **Cold start** — the very first grouped-convolution call, before any warmup,
   into a freshly created MIOpen cache directory. This is the honest measure of
   "how long until my first image".
2. **UNet-shaped convolution stack** — SDXL-proportioned grouped convolutions at
   128×128, timed with HIP events; median and median-absolute-deviation reported.
3. **Attention** — multi-head SDPA at 4096 tokens, plus a per-kernel sweep.
4. **Denoise loop** — 12 steps of conv + attention + group-norm at 96×96 latent
   resolution, which is what captures allocator and residency behaviour that
   single-op timings miss.

Every candidate gets **its own MIOpen cache directory**. Sharing one would make
"cold start" meaningless, because candidate 2 would inherit the database candidate
1 had just written.

### Three measurement traps the engine has to defeat

Benchmarking a GPU honestly turned out to be most of the work. Three separate
effects each produced confidently wrong results before being identified and fixed:

**1. Precision.** The workload must run in the precision the tools actually use.
An early version defaulted to `"auto"` precision and the worker's dtype chain fell
through to **fp32**. That single bug made the fused attention kernels read 15.7 ms
instead of 2.9 ms and crowned the slowest kernel (`MATH`) as the fastest — a 5x
error that looked exactly like a real kernel difference. The engine now resolves
`"auto"` to bf16 with an fp16 fallback, and verifies the device can compute in the
chosen dtype.

**2. GPU cold state.** The first denoise loop of a session takes **104 ms per
step**; every subsequent run of the *same* configuration takes ~16 ms. A 41% swing
from clocks ramping and first-touch page mapping, large enough to decide a
benchmark on its own. The sweep now begins with a warm-up pass whose result is
measured and discarded.

**3. Drift over a long run.** Even after warm-up, a multi-minute sweep can drift —
43% in one observed run. Because the candidate measurements are compared against
the baseline, drift on the baseline silently invalidates everything else. The
engine measures a reference configuration both before and after the sweep, and if
the two disagree by more than 25% it **discards the whole run** and tells you to
retry rather than reporting a result it cannot stand behind.

Each of these was found by the engine disagreeing with a hand measurement. That is
the intended workflow: when a number looks surprising, reproduce it by hand before
believing it.

### Honesty rules

The tuner is built to under-claim rather than over-claim:

- **Numerical validation.** Fused attention kernels are compared against an eager
  reference. Anything deviating more than 2% relative L2 is rejected outright — a
  fast-but-wrong kernel must never win.
- **Noise rejection.** A candidate whose measurement spread exceeds 20% of its
  median is discarded with the advice to close other GPU workloads.
- **A noise floor.** If the best candidate is less than 3% ahead of the defaults,
  the result is reported as *inconclusive* and **nothing is applied**.
- **Tie-break by safety.** Candidates within 4% of each other are a tie, and the
  least aggressive VRAM mode wins. Without this, an OOM-prone profile can win a 2%
  "victory" indistinguishable from noise.
- **Isolation.** Each candidate runs in its own subprocess, so a driver hang, OOM
  or segfault kills only that candidate.

---

## The levers that are real

### 1. MIOpen convolution find-db mode

MIOpen must pick a convolution algorithm for each shape. In `NORMAL` mode it
*searches* on first use and writes the answer to a database; in `FAST` mode it reads
the database. If the database is not persisted between launches, every start pays
the search again.

```bash
export MIOPEN_USER_DB_PATH=~/.config/rocm-wsl-ai/miopen
export MIOPEN_CUSTOM_CACHE_DIR=~/.config/rocm-wsl-ai/miopen
export MIOPEN_FIND_MODE=FAST        # reuse the persisted tuning database
export MIOPEN_FIND_ENFORCE=NONE     # don't re-search what is already known
```

Measured on the reference machine, with a cold per-run cache, in both candidate
orders to rule out warm-up effects:

| Setting | Cold start | Steady-state conv | Denoise step |
|---|---|---|---|
| `FIND_MODE=NORMAL` | **~2200 ms** | 0.79 ms | **~16.5 ms** |
| `FIND_MODE=FAST` | **~1000 ms** | 0.80 ms | **~8.5 ms** |

Order-independent and reproducible. The denoise-loop difference is the one that
matters in practice: MIOpen search work lands inside the first sampling steps, so
it shows up as a per-step cost as well as a startup cost.

> The toolkit sets these paths for **every** tool through `lib/launch.sh`, not only
> for tools launched via a tuned profile, so the benefit is not opt-in.

### 2. VRAM residency

ComfyUI 0.34.0's flags are easy to misread. From its own source:

| Flag | What it actually does |
|---|---|
| `--lowvram` | Sets `VRAMState.LOW_VRAM`. The model is split into per-block chunks loaded and freed around each sampling step. |
| `--disable-smart-memory` | Despite the name, **stops ComfyUI freeing models between prompts** (`model_management` unload loop). Keeps weights warm. |
| `--highvram` | Keep everything resident. Fastest when it fits; the tightest fit. |
| `--vram-headroom N` | Keep N GB genuinely free so Windows and your desktop never lose the GPU. |

The previous version of this toolkit hardcoded `--lowvram --disable-pinned-memory`
for everyone. On a 24 GB card that forces the slow chunked path for no reason. You
can see it happening in ComfyUI's own log:

```text
# with --lowvram
[INFO] Set vram state to: LOW_VRAM

# with the default
[INFO] Set vram state to: NORMAL_VRAM
```

The tuner now derives these flags from measurement, and `lib/launch.sh` validates
each one against the installed ComfyUI's actual `--help` output before passing it.

### 3. Attention kernel

PyTorch on ROCm ships several SDPA kernels whose relative speed is GPU-specific.
Measured on `gfx1100` at 4096 tokens:

| Kernel | Time | Usable |
|---|---|---|
| `EFFICIENT_ATTENTION` | 2.95 ms | yes |
| `FLASH_ATTENTION` | 2.97 ms | yes |
| `MATH` | 13.67 ms | yes (4.6× slower) |
| `CUDNN_ATTENTION` | — | no — aborts on ROCm |

So there **is** real headroom here if you end up on `MATH`. But the two fused
kernels differ by 0.7%, and PyTorch's dispatcher already prefers a fused kernel, so
the engine **measures and reports** this without forcing it. Forcing it would mean
monkey-patching `scaled_dot_product_attention` for a gain inside the noise floor —
complexity that can only break generations.

If you want to pin it yourself, ComfyUI exposes `--use-pytorch-cross-attention`,
`--use-sage-attention`, `--use-flash-attention` and `--use-ck-attention`.

---

## The levers that are folklore

Removing these was a large part of this rewrite.

### `MIGRAPHX_MLIR_USE_SPECIFIC_OPS`

The old auto-tuner's four "profiles" differed mainly in this variable. MIGRAPHX is
a **separate inference runtime**; PyTorch does not dispatch through it unless
`torch_migraphx` is explicitly installed and used. Setting the variable changes
nothing for ComfyUI. It was removed.

### `PYTORCH_HIP_ALLOC_CONF` — actively harmful

An earlier version of this toolkit *migrated users towards* this variable. On
PyTorch 2.9.1+rocm7.2.3 (`gfx1100`), setting it makes the interpreter **segfault on
import**:

```text
$ PYTORCH_HIP_ALLOC_CONF='{"backend":"cudaMallocAsync"}' python3 -c "import torch"
Segmentation fault (core dumped)      # exit -11
```

Isolated against the alternatives:

| Setting | Result |
|---|---|
| nothing | fine |
| `PYTORCH_ALLOC_CONF={"backend":"cudaMallocAsync"}` | fine |
| `PYTORCH_HIP_ALLOC_CONF={...}` | **SIGSEGV** |
| both | **SIGSEGV** |

The toolkit now never sets it, strips it from the environment before launching
anything, warns you if it finds it in your shell, and has a regression test in
`perf_engine.py doctor` that fails if a profile ever emits it again.

### Allocator backend and `expandable_segments`

Tested (`cudaMallocAsync`, `expandable_segments:True/False`) and dropped: no
measurable effect on diffusion-shaped work, and one of the spellings crashes. The
tuner no longer emits `PYTORCH_ALLOC_CONF` at all in the default profile, so the
"defaults" it measures are genuinely default.

### `--no-half` on web UIs

The old SD.Next launcher always passed `--no-half --no-half-vae`. Those are
workarounds for specific situations, and `--no-half` forces fp32 everywhere. This
is easy to get backwards on AMD: RDNA3 in particular has weak fp16 throughput
relative to its fp32 and bf16, so blanket precision flags can cost a lot. The
launcher now passes only what is needed to select the ROCm backend and leaves
precision to the tool, with a documented escape hatch in `user.env`.

---

## Measuring your own changes

Any performance claim for this project should be reproducible. Run the benchmark
twice, in different candidate orders, and check that the winner is stable:

```bash
# full run, saves a JSON report
scripts/utils/perf_engine.py bench --save-report

# reversed candidate order, for the shortlist
scripts/utils/perf_engine.py bench --only miopen-fast,baseline --no-denoise
```

Guidance:

- **Close games, browsers and other GPU work first.** The tuner will reject noisy
  measurements, but a clean run is a better run.
- **`--quick`** for a fast pass, **`--iters 80 --warmup 8`** when the difference is
  small and you need confidence. The menu's *thorough* mode does the latter.
- **`--dry-run`** lists candidates without running anything.
- Results land in `~/.config/rocm-wsl-ai/last_benchmark.json`, and the full
  provenance (probe, per-candidate metrics, verdict) is in `perf_profile.json`.

If you are contributing a performance change, include the raw report. A claim
without a measurement will not be merged — see [`CONTRIBUTING.md`](../CONTRIBUTING.md).
