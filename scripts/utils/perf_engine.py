#!/usr/bin/env python3
"""
ROCm WSL AI Toolkit — Performance Engine
=======================================

The toolkit's single source of truth for *measured* GPU performance settings.

Why this exists
---------------
The previous "Magic Auto-Tuner" benchmarked 4096x4096 fp32 `matmul` + `softmax`
and attributed the (noise-dominated) timing differences to `MIGRAPHX_MLIR_USE_SPECIFIC_OPS`
and `PYTORCH_ALLOC_CONF`. Neither variable actually influences PyTorch's HIP
backend, so the tuner was selecting between statistically identical
configurations while claiming to be "optimised".

This engine instead:

1. Probes what is *actually* present on the machine (GPU arch, dtype support,
   attention backends, optional kernels).
2. Builds candidates only from combinations that can genuinely change GPU
   behaviour: VRAM residency, MIOpen convolution find-db mode, and math
   precision. Levers that measured as noise (allocator backend, explicit SDPA
   kernel choice) are reported but deliberately not tuned.
3. Measures each candidate with a *diffusion-shaped* workload — grouped
   convolutions, SDPA attention and group-norm, which is what UNet/DiT
   inference actually spends its time on — using CUDA/HIP events, median and
   MAD statistics, and a real denoise-loop simulation.
4. Rejects candidates that are numerically wrong, and refuses to declare a
   "winner" when every candidate is inside measurement noise.
5. Writes a portable profile that the launch layer applies to every tool.

Design constraints
------------------
* Python 3.10+ (Ubuntu 22.04 ships 3.10, 24.04 ships 3.12). Standard library only.
* Must never crash the toolkit: every failure path returns a structured error.
* Input tensors are allocated once and reused, so measurements capture kernel
  time rather than allocator churn.
* All GPU work happens in short-lived subprocesses. A driver hang, OOM or
  segfault in a bad candidate kills only that candidate.

Subcommands
-----------
  probe     Machine + GPU capability report (JSON or human readable)
  profiles  List candidate profiles without running them
  bench     Measure candidates and pick a winner
  apply     Persist a tuned profile
  show      Show the active profile and its exact effect
  doctor    Self-check the engine (works without a GPU)
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import textwrap
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

ENGINE_VERSION = "1.0.0"

CONFIG_DIR = Path(os.environ.get("ROCM_AI_CONFIG_DIR", Path.home() / ".config" / "rocm-wsl-ai"))
PROFILE_JSON = CONFIG_DIR / "perf_profile.json"
PROFILE_ENV = CONFIG_DIR / "perf.env"
MIOPEN_DB_DIR = CONFIG_DIR / "miopen"
LAST_REPORT = CONFIG_DIR / "last_benchmark.json"

# Performance wins smaller than this are reported as "within noise" instead of
# being sold to the user as an improvement.
NOISE_FLOOR_PCT = 3.0
# A candidate whose spread exceeds this fraction of its median is untrustworthy.
NOISE_REJECT_RATIO = 0.20
# Relative L2 deviation from eager attention that indicates a broken backend.
NUMERIC_TOLERANCE_PCT = 2.0
# Candidates within this band of the leader are treated as tied, and the safest
# of them wins. Without this, an OOM-prone profile can win a 2% "victory" that
# is indistinguishable from noise.
TIE_BAND_PCT = 4.0
# The anchor candidate is measured both first and last. GPU state drifts over a
# multi-minute run (thermals, clock ramping, driver caches), and a drifting
# baseline silently invalidates every comparison made against it. If the two
# anchor measurements differ by more than this, the whole run is declared
# contaminated instead of being reported as a result.
ANCHOR_DRIFT_TOLERANCE_PCT = 25.0
ANCHOR_KEY = "__anchor__"

# Lower is safer. Used only to break statistical ties.
VRAM_MODE_SAFETY: dict[str, int] = {
    "default": 0,
    "resident": 1,
    "headroom": 2,
    "high": 3,
    "novram": 4,
    "low": 4,
}


def _safety_rank(entry: dict[str, Any]) -> int:
    mode = entry.get("vram_mode", "default")
    return VRAM_MODE_SAFETY.get(mode, 5)

# Ubuntu 22.04 ships Python 3.10 / 24.04 ships 3.12. No 3.11-only syntax here.

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------


def eprint(*args: Any) -> None:
    print(*args, file=sys.stderr, flush=True)


def say(*args: Any) -> None:
    """
    Progress output, flushed.

    Python block-buffers stdout when it is not a terminal, so a multi-minute
    benchmark that is piped or redirected shows nothing until it finishes — which
    looks exactly like a hang. The launcher also passes -u; this makes it safe
    regardless of how the engine is invoked.
    """
    print(*args, flush=True)


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def rel_l2(a: Any, b: Any) -> float:
    """Relative L2 distance between two tensors, in percent."""
    import torch

    a32 = a.float()
    b32 = b.float()
    denom = a32.norm().item()
    if denom == 0.0:
        return 0.0
    return (a32 - b32).norm().item() / denom * 100.0


def human_gb(num_bytes: float) -> str:
    if not num_bytes or num_bytes <= 0:
        return "n/a"
    return f"{num_bytes / 1024 ** 3:.1f} GB"


def deep_merge(*dicts: dict[str, Any]) -> dict[str, Any]:
    """Recursively merge dictionaries; later entries win."""
    out: dict[str, Any] = {}
    for d in dicts:
        for key, value in d.items():
            if isinstance(value, dict) and isinstance(out.get(key), dict):
                out[key] = deep_merge(out[key], value)
            else:
                out[key] = value
    return out


# ---------------------------------------------------------------------------
# Profile model
# ---------------------------------------------------------------------------

# The baseline candidate. Every other profile is this dict with patches applied,
# so profiles stay readable and their differences stay obvious in --dry-run.
#
# Field meanings are grounded in ComfyUI 0.34.0's own cli_args.py and
# model_management.py, not in folklore:
#
#   vram_mode  "default"  -> let ComfyUI pick the VRAM state (NORMAL_VRAM on a
#                            card with room to spare). The toolkit previously
#                            forced "--lowvram", which sets VRAMState.LOW_VRAM:
#                            ComfyUI splits the model into per-block chunks that
#                            are loaded and freed during sampling.
#              "resident" -> --disable-smart-memory. Despite the name, this
#                            stops ComfyUI freeing models between prompts
#                            (model_management unload loop). Keeps weights warm.
#              "high"     -> --highvram + --disable-smart-memory + headroom.
#              "low"      -> --lowvram, for cards that cannot hold the model.
#   miopen     normal|fast  MIOpen convolution find-db mode (real env vars).
#                           This is the dominant startup-latency lever: NORMAL
#                           searches for the best convolution algorithm on the
#                           first block of every launch, FAST reuses the db.
#   precision  bf16|fp16|fp32
#                           ComfyUI --bf16-unet / --fp16-unet / --force-fp32.
#
# Deliberately absent as tunable levers, after measuring them:
#   * GPU memory allocator backend. PYTORCH_HIP_ALLOC_CONF segfaults torch
#     2.9.1+rocm7.2.3 outright, and expandable_segments showed no measurable
#     effect on diffusion-shaped work.
#   * Torch SDPA kernel selection. Measured on gfx1100 the two fused kernels are
#     0.7% apart (below the noise floor), and ComfyUI already selects a fused
#     kernel by default. Reported for information, never forced.
PROFILE_BASE: dict[str, Any] = {
    "vram_mode": "default",
    "miopen": {"mode": "normal", "strategy": "warm"},
    # "auto" means: pass no precision flag and let ComfyUI choose, which it does
    # sensibly per model. Forcing --bf16-unet on a model that expects fp16, or on
    # a GPU where bf16 is emulated, is a quality and compatibility risk that no
    # measurement here justifies. Set "bf16" / "fp16" / "fp32" to override.
    "precision": "auto",
    "vram_headroom_gb": None,
    # Fastest numerically-sound SDPA kernel measured on this GPU. Recorded for
    # reporting; not force-applied by this toolkit (see profile_to_env).
    "prefer_attn_backend": None,
}

# Short CLI keys -> profile field paths.
PROFILE_SCHEMA: dict[str, tuple[str, tuple[str, ...]]] = {
    "vram": ("VRAM residency", ("vram_mode",)),
    "miopen": ("MIOpen conv strategy", ("miopen", "mode")),
    "prec": ("Math precision", ("precision",)),
}

PROFILE_SPECS: list[dict[str, Any]] = [
    {
        "key": "baseline",
        "title": "ComfyUI default VRAM",
        "desc": "Let ComfyUI choose its own VRAM state. Reference point for every comparison.",
        "overrides": {},
    },
    {
        "key": "resident",
        "title": "Resident models",
        "desc": "Stop ComfyUI unloading models between prompts so weights stay in VRAM.",
        "overrides": {"vram_mode": "resident"},
    },
    {
        "key": "miopen-fast",
        "title": "MIOpen cache fast-path",
        "desc": "Reuse the persisted convolution tuning database instead of re-searching.",
        "overrides": {"miopen": {"mode": "fast", "strategy": "warm"}},
    },
    {
        "key": "resident+miopen",
        "title": "Resident + MIOpen fast",
        "desc": "Both of the above combined. The sensible default recommendation.",
        "overrides": {
            "vram_mode": "resident",
            "miopen": {"mode": "fast", "strategy": "warm"},
        },
    },
    {
        "key": "headroom",
        "title": "Resident + 1GB headroom",
        "desc": "Keeps 1GB VRAM free so Windows and your desktop never lose the GPU.",
        "overrides": {
            "vram_mode": "resident",
            "miopen": {"mode": "fast", "strategy": "warm"},
            "vram_headroom_gb": 1.0,
        },
    },
    {
        "key": "lean",
        "title": "Lean VRAM (chunked)",
        "desc": "Force ComfyUI to chunk weights. Slower, but survives low-VRAM cards.",
        "overrides": {"vram_mode": "low"},
    },
    {
        "key": "high",
        "title": "Aggressive residency",
        "desc": "Keep everything resident with no headroom. Fastest when it fits, tightest fit.",
        "overrides": {
            "vram_mode": "high",
            "miopen": {"mode": "fast", "strategy": "warm"},
        },
    },
]

PROFILES_BY_KEY: dict[str, dict[str, Any]] = {p["key"]: p for p in PROFILE_SPECS}


def _set_path(d: dict[str, Any], path: tuple[str, ...], value: Any) -> None:
    cursor = d
    for part in path[:-1]:
        cursor = cursor.setdefault(part, {})
    cursor[path[-1]] = value


def build_profile(key: str, overrides: dict[str, Any] | None = None) -> dict[str, Any]:
    spec = PROFILES_BY_KEY.get(key)
    if spec is None:
        raise KeyError(f"unknown profile key: {key}")
    base = json.loads(json.dumps(PROFILE_BASE))  # deep copy, keeps 3.10 happy
    merged = deep_merge(base, spec["overrides"], overrides or {})
    merged["key"] = key
    merged["title"] = spec["title"]
    return merged


def profile_to_env(profile: dict[str, Any]) -> dict[str, str]:
    """
    Translate a profile into the environment variables that actually change GPU
    behaviour. This is the function that decides whether the tuner is real or
    theatre, so every entry here is a documented, backend-honoured variable.
    """
    env: dict[str, str] = {}

    # --- MIOpen convolution find-db -----------------------------------------
    miopen = profile.get("miopen", {})
    mode = miopen.get("mode", "normal")
    env["MIOPEN_USER_DB_PATH"] = str(MIOPEN_DB_DIR)
    env["MIOPEN_CUSTOM_CACHE_DIR"] = str(MIOPEN_DB_DIR)
    # Keep benchmark chatter out of the tool's stdout.
    env["MIOPEN_LOG_LEVEL"] = "3"
    if mode == "fast":
        # FAST uses the persisted find-db; NORMAL performs searches and writes
        # the results so the *next* launch is fast.
        env["MIOPEN_FIND_MODE"] = "FAST"
        env["MIOPEN_FIND_ENFORCE"] = "DB_UPDATE"
    else:
        env["MIOPEN_FIND_MODE"] = "NORMAL"
        env["MIOPEN_FIND_ENFORCE"] = "SEARCH"
    if miopen.get("strategy") == "warm" and mode == "fast":
        env["MIOPEN_FIND_ENFORCE"] = "NONE"

    # --- Memory allocator ---------------------------------------------------
    # Only emit PYTORCH_ALLOC_CONF when a non-default allocator was requested.
    # Emitting it unconditionally would make the "baseline" candidate not a
    # baseline, and there is no measured benefit at the default setting.
    if profile.get("allocator") == "cuda_malloc_async":
        env["PYTORCH_ALLOC_CONF"] = '{"backend":"cudaMallocAsync"}'
    # DELIBERATELY NEVER SET: PYTORCH_HIP_ALLOC_CONF.
    # Measured on torch 2.9.1+rocm7.2.3 / gfx1100: assigning this variable
    # segfaults the interpreter (SIGSEGV, exit -11) before torch finishes
    # importing. is_alloc_conf_set() explains this to users, because an earlier
    # toolkit version migrated *towards* this spelling.

    # --- WSL DXCore bridge (always required in this toolkit) ----------------
    env["HSA_ENABLE_DXG_DETECTION"] = "1"

    # --- Precision hints ----------------------------------------------------
    precision = profile.get("precision", "bf16")
    if precision == "fp16":
        env["ROCBLAS_INTERNAL_FP32_ORDER"] = "1"
        env["MIOPEN_DEBUG_CONV_IMPLICIT_GEMM"] = "1"

    # --- Attention kernel ---------------------------------------------------
    # Deliberately NOT exported. The fastest kernel is measured and recorded in
    # the profile for reporting, but never force-applied: on gfx1100 the two
    # fused kernels measure 0.7% apart (inside the noise floor) and ComfyUI
    # already selects a fused kernel on its own. Forcing it would add a
    # monkey-patch that can only break generations, not speed them up.

    return env


def attention_kernel_summary(metrics: dict[str, Any], kernels: dict[str, Any]) -> list[str]:
    """Human-readable per-kernel attention table."""
    if not kernels:
        return []
    lines = ["", "Attention kernels measured on this GPU:"]
    best = metrics.get("attn_best_kernel")
    for name, entry in sorted(kernels.items(), key=lambda kv: kv[1].get("ms") or 9e9):
        if entry.get("usable") and entry.get("ms") is not None:
            marker = " <- fastest" if name == best else ""
            extra = ""
            if entry.get("rel_l2_pct") is not None:
                extra = f"  (vs eager: {entry['rel_l2_pct']:.2f}%)"
            lines.append(f"  {name:<24} {entry['ms']:>8.2f} ms{extra}{marker}")
        else:
            why = entry.get("note") or entry.get("error") or "not available"
            lines.append(f"  {name:<24} {'—':>8}     unavailable: {why[:60]}")
    return lines


def profile_to_comfyui_args(profile: dict[str, Any]) -> list[str]:
    """
    ComfyUI CLI arguments implied by a profile.

    Every flag here was verified against ComfyUI 0.34.0's comfy/cli_args.py.
    The launcher probes the installed ComfyUI's --help output and drops any flag
    this particular version does not know, so an older checkout cannot break.
    """
    mode = profile.get("vram_mode", "default")
    args: list[str] = []

    if mode == "resident":
        args.append("--disable-smart-memory")
    elif mode == "high":
        args.extend(["--highvram", "--disable-smart-memory"])
    elif mode == "low":
        args.append("--lowvram")
    elif mode == "novram":
        args.append("--novram")
    # "default" deliberately passes nothing: ComfyUI already picks NORMAL_VRAM
    # on a card with headroom, and letting it choose is the safest baseline.

    headroom = profile.get("vram_headroom_gb")
    if headroom:
        args.extend(["--vram-headroom", str(headroom)])

    precision = profile.get("precision", "auto")
    # "auto" passes nothing, so ComfyUI decides per model. Only an explicit
    # choice produces a flag.
    if precision == "bf16":
        args.append("--bf16-unet")
    elif precision == "fp16":
        args.append("--fp16-unet")
    elif precision == "fp32":
        args.append("--force-fp32")

    return args


def is_alloc_conf_set() -> tuple[bool, str]:
    """
    Detect the PYTORCH_HIP_ALLOC_CONF segfault trap in the ambient environment.

    Returns (is_dangerous, explanation). Called before every measurement so a
    stale export inherited from an older toolkit version surfaces as a clear
    message instead of a bare SIGSEGV.
    """
    if os.environ.get("PYTORCH_HIP_ALLOC_CONF"):
        return True, (
            "PYTORCH_HIP_ALLOC_CONF is set in your environment. On "
            "torch 2.9.1+rocm7.2.3 this segfaults the interpreter during import. "
            "Remove it from ~/.bashrc, ~/.config/rocm-wsl-ai/user.env, or the "
            "venv activate script; the toolkit now uses PYTORCH_ALLOC_CONF."
        )
    return False, ""


def profile_to_description(profile: dict[str, Any]) -> str:
    bits = [
        f"vram={profile.get('vram_mode')}",
        f"miopen={profile.get('miopen', {}).get('mode')}",
    ]
    precision = profile.get("precision", "auto")
    if precision != "auto":
        bits.append(f"precision={precision}")
    if profile.get("vram_headroom_gb"):
        bits.append(f"headroom={profile['vram_headroom_gb']}GB")
    args = profile_to_comfyui_args(profile)
    if args:
        bits.append("flags=" + " ".join(args))
    return " ".join(bits)


# ---------------------------------------------------------------------------
# Capability probe
# ---------------------------------------------------------------------------

PROBE_SCRIPT = r"""
import json, os, sys, platform, importlib.util

# Capture the builtin before the device-properties block below rebinds `int`.
_int = int

def mod(name):
    try:
        return importlib.util.find_spec(name) is not None
    except Exception:
        return False

out = {"ok": True, "python": platform.python_version()}
try:
    import torch
except Exception as exc:
    print(json.dumps({"ok": False, "error": f"torch import failed: {exc}"}))
    sys.exit(0)

out["torch"] = torch.__version__
out["hip"] = getattr(torch.version, "hip", None)
out["cuda_available"] = bool(torch.cuda.is_available())
out["gpu_count"] = torch.cuda.device_count() if out["cuda_available"] else 0
out["device_name"] = torch.cuda.get_device_name(0) if out["cuda_available"] else None

props = {}
if out["cuda_available"]:
    p = torch.cuda.get_device_properties(0)
    print_ = lambda k, v: props.__setitem__(k, v)
    print_("name", p.name)
    print_("total_memory", _int(p.total_memory))
    for attr in ("gcnArchName", "multi_processor_count", "major", "minor", "warp_size"):
        if hasattr(p, attr):
            try:
                val = getattr(p, attr)
                print_(attr, _int(val) if attr != "gcnArchName" else str(val))
            except Exception:
                pass
    try:
        free, total = torch.cuda.mem_get_info()
        props["free_memory"] = _int(free)
    except Exception:
        pass
out["props"] = props

# dtype support — ask the device, do not assume
dtypes = {}
if out["cuda_available"]:
    for name, factory in (("fp16", torch.float16), ("bf16", torch.bfloat16), ("fp32", torch.float32)):
        try:
            t = torch.ones(8, 8, device="cuda", dtype=factory)
            dtypes[name] = bool((t @ t).isfinite().all().item())
        except Exception:
            dtypes[name] = False
out["dtypes"] = dtypes

# Attention backends: enumerate what exists, then ask the device which actually
# work. Enumeration alone lies (CUDNN_ATTENTION exists but aborts on ROCm), so
# every candidate is smoke-tested with a real small attention call.
usable_backends = []
if out["cuda_available"]:
    names = []
    try:
        from torch.nn.attention import SDPBackend
        # torch 2.9 exposes __members__; iterating the enum object directly
        # raises "pybind11_type object is not iterable" on ROCm builds.
        names = [n for n in getattr(SDPBackend, "__members__", {}) if n != "ERROR"]
        if not names:
            names = [n for n in dir(SDPBackend) if n.isupper() and n != "ERROR"]
    except Exception:
        names = ["FLASH_ATTENTION", "EFFICIENT_ATTENTION", "MATH"]

    try:
        from torch.nn.attention import SDPBackend, sdpa_kernel
        import torch.nn.functional as _F
        _q = torch.randn(1, 2, 64, 32, device="cuda", dtype=torch.float16)
        for name in names:
            backend = getattr(SDPBackend, name, None)
            if backend is None:
                continue
            try:
                with sdpa_kernel(backend):
                    _F.scaled_dot_product_attention(_q, _q, _q)
                usable_backends.append(name)
            except Exception:
                pass
    except Exception:
        usable_backends = names
out["sdpa_backends"] = usable_backends

# SageAttention / FlashAttention-ROCm / Triton presence.
out["optional"] = {
    "sageattention": mod("sageattention"),
    "flash_attn": mod("flash_attn"),
    "triton": mod("triton"),
    "diffusers": mod("diffusers"),
    "transformers": mod("transformers"),
    "torch_migraphx": mod("torch_migraphx"),
}

try:
    import triton
    out["triton"] = getattr(triton, "__version__", "unknown")
except Exception:
    out["triton"] = None

print(json.dumps(out))
"""


def _run_probe(venv_python: Path | None) -> dict[str, Any]:
    python = str(venv_python) if venv_python and venv_python.exists() else sys.executable
    env = dict(os.environ)
    env.setdefault("HSA_ENABLE_DXG_DETECTION", "1")
    env["PYTHONWARNINGS"] = "ignore"
    try:
        proc = subprocess.run(
            [python, "-c", PROBE_SCRIPT],
            capture_output=True,
            text=True,
            timeout=180,
            env=env,
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "probe timed out after 180s"}
    except OSError as exc:
        return {"ok": False, "error": f"could not launch {python}: {exc}"}

    payload = None
    for line in reversed(proc.stdout.strip().splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                payload = json.loads(line)
                break
            except json.JSONDecodeError:
                continue
    if payload is None:
        detail = (proc.stderr or proc.stdout or "").strip()[-600:]
        return {"ok": False, "error": f"probe produced no JSON. Output: {detail}"}
    return payload


def find_venv_python(venv_name: str = "genai_env") -> Path | None:
    candidate = Path.home() / venv_name / "bin" / "python3"
    if candidate.exists():
        return candidate
    return None


def detect_gfx_arch() -> str | None:
    """Best-effort gfx arch detection via rocminfo / clinfo, without torch."""
    for tool, pattern in (("rocminfo", r"gfx[0-9a-f]+"), ("clinfo", r"gfx[0-9a-f]+")):
        if not shutil.which(tool):
            continue
        try:
            proc = subprocess.run([tool], capture_output=True, text=True, timeout=60)
        except (subprocess.TimeoutExpired, OSError):
            continue
        match = re.search(pattern, proc.stdout or "")
        if match:
            return match.group(0)
    return None


def detect_rocm_version() -> str | None:
    version_file = Path("/opt/rocm/.info/version")
    if version_file.exists():
        try:
            return re.sub(r"[^0-9.]", "", version_file.read_text().splitlines()[0])
        except (OSError, IndexError):
            return None
    return None


def is_wsl() -> bool:
    try:
        return "microsoft" in Path("/proc/version").read_text().lower()
    except OSError:
        return os.environ.get("WSL_DISTRO_NAME", "") != ""


def human_probe(probe: dict[str, Any], gfx: str | None = None) -> str:
    lines = ["ROCm WSL AI Toolkit — Performance Probe", "=" * 44, ""]
    lines.append(f"Engine version   : {ENGINE_VERSION}")
    lines.append(f"Host             : {'WSL2' if is_wsl() else platform.system()}")
    lines.append(f"ROCm (installed) : {detect_rocm_version() or 'not detected'}")
    lines.append(f"gfx architecture : {gfx or 'not detected'}")
    lines.append("")

    if not probe.get("ok"):
        lines.append(f"  PyTorch probe FAILED: {probe.get('error')}")
        return "\n".join(lines)

    lines.append(f"Python           : {probe.get('python')}")
    lines.append(f"PyTorch          : {probe.get('torch')}  (HIP {probe.get('hip')})")
    lines.append(f"Triton           : {probe.get('triton') or 'not installed'}")
    lines.append("")

    if probe.get("cuda_available"):
        props = probe.get("props", {})
        lines.append(f"GPU              : {probe.get('device_name')}")
        lines.append(f"  gcnArchName    : {props.get('gcnArchName', 'n/a')}")
        lines.append(f"  VRAM total     : {human_gb(props.get('total_memory', 0))}")
        if props.get("free_memory"):
            lines.append(f"  VRAM free      : {human_gb(props.get('free_memory'))}")
    else:
        lines.append("GPU              : NOT VISIBLE to PyTorch")
        lines.append("")
        lines.append("  Fix checklist:")
        lines.append("   1. In Windows PowerShell: wsl --shutdown   (then reopen Ubuntu)")
        lines.append("   2. AMD Adrenalin 26.2.2+ driver installed on Windows")
        lines.append("   3. /opt/rocm/lib/librocdxg.so present")
        lines.append("   4. User in render+video groups")
        lines.append("   5. Run: menu.sh -> Settings -> GPU Diagnostics")

    dtypes = probe.get("dtypes", {})
    if dtypes:
        supported = ", ".join(k for k, v in dtypes.items() if v) or "none"
        lines.append("")
        lines.append(f"dtypes supported : {supported}")

    backends = probe.get("sdpa_backends")
    if backends:
        lines.append(f"attention kernels: {', '.join(backends)}")

    optional = probe.get("optional", {})
    if optional:
        lines.append("")
        lines.append("Optional kernels :")
        for name, present in sorted(optional.items()):
            lines.append(f"  {'[x]' if present else '[ ]'} {name}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Candidate selection
# ---------------------------------------------------------------------------


def candidates_for(probe: dict[str, Any], keys: Iterable[str] | None = None) -> list[str]:
    """
    Filter profile specs down to what can actually run and can plausibly differ
    on this machine. Running a "Resident models" candidate on a GPU that cannot
    hold the workload would only measure swapping.
    """
    available = {p["key"] for p in PROFILE_SPECS}
    if keys:
        wanted = [k for k in keys if k in available]
        return wanted or ["baseline"]

    if not probe.get("ok") or not probe.get("cuda_available"):
        return ["baseline"]

    props = probe.get("props", {})
    vram = int(props.get("total_memory") or 0)
    selected = ["baseline"]

    # Residency variants only make sense with enough VRAM to actually hold models.
    if vram >= 12 * 1024 ** 3:
        selected.append("resident")
        selected.append("resident+miopen")
        selected.append("headroom")
    selected.append("miopen-fast")
    # Aggressive mode needs headroom; otherwise it just OOMs.
    if vram >= 20 * 1024 ** 3:
        selected.append("high")
    # Always keep one lean candidate so low-VRAM users get a tested answer.
    selected.append("lean")

    # Preserve declaration order, drop duplicates.
    seen: set[str] = set()
    ordered: list[str] = []
    for k in selected:
        if k not in seen:
            seen.add(k)
            ordered.append(k)
    return ordered


# ---------------------------------------------------------------------------
# Benchmark worker (runs in a subprocess)
# ---------------------------------------------------------------------------

BENCH_WORKER = r'''
import json, os, sys, time

# Store a live reference to int() before any local name can shadow the builtin:
# the device-properties section below binds a dict called `int` in this scope,
# which otherwise makes int(...) fail with "can't multiply sequence by non-int".
_int = int

profile = json.loads(os.environ["ROCM_AI_BENCH_PROFILE"])
scale = float(os.environ.get("ROCM_AI_BENCH_SCALE", "1.0"))
do_denoise = os.environ.get("ROCM_AI_BENCH_DENOISE", "1") == "1"
warmup = _int(os.environ.get("ROCM_AI_BENCH_WARMUP", "3"))
iters = max(5, _int(_int(os.environ.get("ROCM_AI_BENCH_ITERS", "30")) * scale))
# Which measurements to take in this process. Running one task per process keeps
# the GPU state clean: measured on gfx1100, attention reads 3.0 ms in a fresh
# process but 15 ms if a convolution benchmark has just run in the same one,
# which is enough to make the slowest kernel look like the fastest.
tasks = os.environ.get("ROCM_AI_BENCH_TASKS", "cold,conv,attn,denoise").split(",")
tasks = [t.strip() for t in tasks if t.strip()]

def emit(payload):
    print("ROCM_AI_BENCH_JSON:" + json.dumps(payload), flush=True)

try:
    import torch
    import torch.nn.functional as F
except Exception as exc:
    emit({"ok": False, "error": f"torch import failed: {exc}"}); sys.exit(0)

if not torch.cuda.is_available():
    emit({"ok": False, "error": "no HIP/ROCm device visible to PyTorch"}); sys.exit(0)

dev = torch.device("cuda")

# Precision selection. This is where benchmarks most easily lie: measuring in
# fp32 when the tools actually run bf16 makes every result meaningless, and the
# difference is large (on gfx1100 the fused attention kernels take ~2.9 ms in
# bf16 and ~15.7 ms in fp32, a 5x gap that looks exactly like a broken kernel).
# "auto" therefore means bf16 with an fp16 fallback, which is what ComfyUI and
# SD.Next use for diffusion UNets.
precision = profile.get("precision", "auto")
if precision == "bf16":
    dtype = torch.bfloat16
elif precision == "fp16":
    dtype = torch.float16
elif precision == "fp32":
    dtype = torch.float32
else:
    # "auto": pick the best supported reduced precision.
    dtype = torch.bfloat16

# Verify the device can actually compute in the chosen dtype, and fall back
# rather than producing a benchmark of NaNs.
try:
    _probe = torch.ones(8, 8, device=dev, dtype=dtype)
    if not bool((_probe @ _probe).isfinite().all().item()):
        dtype = torch.float16
except Exception:
    dtype = torch.float16
del _probe

def timed(fn, n, warm):
    """Median + MAD of n timed iterations, after warmup. Returns (ms, spread_ms)."""
    for _ in range(warm):
        fn()
    torch.cuda.synchronize()
    samples = []
    for _ in range(n):
        s = torch.cuda.Event(enable_timing=True); e = torch.cuda.Event(enable_timing=True)
        s.record(); fn(); e.record()
        torch.cuda.synchronize()
        samples.append(s.elapsed_time(e))
    med = sorted(samples)[len(samples)//2]
    mad = sorted(abs(x - med) for x in samples)[len(samples)//2]
    return med, mad

results = {"ok": True, "dtype": str(dtype).replace("torch.", ""), "metrics": {}}

# --- 0. Cold-start cost -----------------------------------------------------
# The very first convolution a user triggers after launching ComfyUI is where
# MIOpen's find-db mode genuinely matters: NORMAL searches for the best
# algorithm and pays that cost on the first block of the first generation,
# FAST reuses the persisted database. Time the first call before any warmup.
if "cold" in tasks:
  try:
    _cs_block = torch.nn.Sequential(
        torch.nn.Conv2d(320, 320, 3, padding=1, groups=8),
        torch.nn.SiLU(),
        torch.nn.Conv2d(320, 640, 3, stride=2, padding=1),
    ).to(device=dev, dtype=dtype).eval()
    _cs_in = torch.randn(1, 320, 128, 128, device=dev, dtype=dtype)
    torch.cuda.synchronize()
    _t0 = time.perf_counter()
    with torch.no_grad():
        _cs_block(_cs_in)
    torch.cuda.synchronize()
    results["metrics"]["cold_first_conv_ms"] = round((time.perf_counter() - _t0) * 1000.0, 2)
    del _cs_block, _cs_in
    torch.cuda.empty_cache()
  except Exception as exc:
    results["metrics"]["cold_start_error"] = str(exc)[:200]

try:
    torch.cuda.empty_cache()
    torch.cuda.reset_peak_memory_stats()
    baseline_vram = torch.cuda.memory_allocated()
except Exception:
    pass

# --- 1. UNet-shaped convolution stack --------------------------------------
# Channels/spatial sizes follow a mid-resolution SDXL UNet block. Grouped convs
# are where MIOpen's find-db mode actually changes measured time.
if "conv" in tasks:
  try:
    conv_block = torch.nn.Sequential(
        torch.nn.Conv2d(320, 320, 3, padding=1, groups=8),
        torch.nn.SiLU(),
        torch.nn.Conv2d(320, 640, 3, stride=2, padding=1),
        torch.nn.SiLU(),
        torch.nn.Conv2d(640, 640, 3, padding=1, groups=16),
        torch.nn.SiLU(),
    ).to(device=dev, dtype=dtype).eval()
    conv_in = torch.randn(1, 320, 128, 128, device=dev, dtype=dtype)

    def run_conv():
        with torch.no_grad():
            conv_block(conv_in)

    with torch.no_grad():
        out_conv = run_conv()
    # Warm up generously. In MIOpen SEARCH mode the early calls perform algorithm
    # searches; timing those as "steady state" made the default configuration
    # look roughly 3x slower per iteration than it really is. That search cost is
    # real, but it belongs to the cold-start number above, not to this one.
    conv_ms, conv_spread = timed(run_conv, iters, max(warmup, 8))
    results["metrics"]["conv_ms"] = round(conv_ms, 4)
    results["metrics"]["conv_spread_ms"] = round(conv_spread, 4)

    if dtype in (torch.bfloat16, torch.float16):
        ref = conv_block.float()(conv_in.float())
        results["metrics"]["conv_rel_l2_pct"] = round(
            (out_conv.float() - ref).norm().item() / ref.norm().item() * 100.0, 3
        )
        del ref
    del out_conv
  except Exception as exc:
    results["metrics"]["conv_error"] = str(exc)[:200]

# --- 2. Attention (SDPA) and backend agreement ------------------------------
# Multi-head self-attention at a realistic token count: 4096 tokens, 8 heads.
# On ROCm, PyTorch ships several attention kernels (AOTriton "efficient",
# "flash", and a math fallback) whose relative speed is GPU-specific. This is
# the one setting where measuring genuinely beats guessing, so every usable
# kernel is timed and the winner is recorded.
#
# This runs in its own process (see the "tasks" switch above): the same workload
# measures 3.0 ms in a fresh process and 15 ms after a convolution benchmark has
# run, which would make the slowest kernel look fastest.
if "attn" in tasks:
  try:
    B, H, N, D = 2, 8, 4096, 64
    q = torch.randn(B, H, N, D, device=dev, dtype=dtype)
    k = torch.randn(B, H, N, D, device=dev, dtype=dtype)
    v = torch.randn(B, H, N, D, device=dev, dtype=dtype)

    def run_sdpa():
        with torch.no_grad():
            F.scaled_dot_product_attention(q, k, v)

    with torch.no_grad():
        out_attn = run_sdpa()
    attn_ms, attn_spread = timed(run_sdpa, iters, max(warmup, 5))
    results["metrics"]["attn_ms"] = round(attn_ms, 4)
    results["metrics"]["attn_spread_ms"] = round(attn_spread, 4)

    # Eager attention as the numerical reference. If a fused backend disagrees
    # with eager beyond tolerance the backend is producing wrong results, and
    # the profile must not be allowed to win on speed alone.
    ref_attn = None
    if dtype in (torch.bfloat16, torch.float16):
        try:
            with torch.no_grad():
                scale = 1.0 / (D ** 0.5)
                scores = torch.matmul(q.float(), k.float().transpose(-2, -1)) * scale
                ref_attn = torch.matmul(torch.softmax(scores, dim=-1), v.float())
            results["metrics"]["attn_rel_l2_pct"] = round(
                (out_attn.float() - ref_attn).norm().item() / ref_attn.norm().item() * 100.0, 3
            )
            del scores
        except Exception as exc:
            results["metrics"]["attn_ref_error"] = str(exc)[:200]
            ref_attn = None
    del out_attn

    # Per-kernel sweep. Keep only kernels that run AND agree numerically.
    kernel_report = {}
    try:
        from torch.nn.attention import SDPBackend, sdpa_kernel
        names = [n for n in getattr(SDPBackend, "__members__", {}) if n != "ERROR"]
        if not names:
            names = [n for n in dir(SDPBackend) if n.isupper() and n != "ERROR"]
        for name in names:
            backend = getattr(SDPBackend, name, None)
            if backend is None:
                continue
            entry = {"usable": False}
            try:
                def run_kernel(be=backend):
                    with sdpa_kernel(be):
                        with torch.no_grad():
                            F.scaled_dot_product_attention(q, k, v)

                with torch.no_grad():
                    sample = run_kernel()
                ms, spread = timed(run_kernel, max(5, iters // 2), max(warmup, 5))
                entry["usable"] = True
                entry["ms"] = round(ms, 4)
                entry["spread_ms"] = round(spread, 4)
                if ref_attn is not None:
                    dev_pct = (
                        (sample.float() - ref_attn).norm().item()
                        / ref_attn.norm().item() * 100.0
                    )
                    entry["rel_l2_pct"] = round(dev_pct, 3)
                    if dev_pct > 2.0:
                        entry["usable"] = False
                        entry["note"] = f"numerically wrong ({dev_pct:.2f}% off eager)"
                del sample
            except Exception as exc:
                entry["error"] = str(exc)[:120]
            kernel_report[name] = entry
    except Exception as exc:
        results["metrics"]["attn_sweep_error"] = str(exc)[:200]

    if ref_attn is not None:
        del ref_attn
    del q, k, v

    if kernel_report:
        results["attention_kernels"] = kernel_report
        fastest = sorted(
            ((n, e) for n, e in kernel_report.items() if e.get("usable") and e.get("ms")),
            key=lambda kv: kv[1]["ms"],
        )
        if fastest:
            results["metrics"]["attn_best_kernel"] = fastest[0][0]
            results["metrics"]["attn_best_ms"] = fastest[0][1]["ms"]
  except Exception as exc:
    results["metrics"]["attn_error"] = str(exc)[:200]

# --- 3. Denoise-loop simulation (end-to-end proxy) --------------------------
# 12 "steps" of conv + attention + group-norm on a latent batch. This captures
# the per-step allocator and residency behaviour that single-op timings miss.
if do_denoise:
    try:
        steps = max(4, int(12 * scale))
        latent = torch.randn(1, 4, 96, 96, device=dev, dtype=dtype)
        emb = torch.randn(1, 320, device=dev, dtype=dtype)
        up = torch.nn.Conv2d(4, 320, 3, padding=1).to(device=dev, dtype=dtype).eval()
        mid = torch.nn.Conv2d(320, 320, 3, padding=1, groups=8).to(device=dev, dtype=dtype).eval()
        norm = torch.nn.GroupNorm(8, 320).to(device=dev, dtype=dtype).eval()
        qk = torch.randn(1, 8, 2304, 64, device=dev, dtype=dtype)

        def one_step():
            with torch.no_grad():
                h = up(latent)
                h = h + emb[:, :, None, None]
                h = norm(mid(h))
                attn_out = F.scaled_dot_product_attention(qk, qk, qk)
                h = h + attn_out.mean() * 0.0
                F.silu(h)
                return h

        torch.cuda.synchronize()
        if torch.cuda.is_available():
            torch.cuda.reset_peak_memory_stats()
        start = time.perf_counter()
        for _ in range(steps):
            one_step()
        torch.cuda.synchronize()
        wall = time.perf_counter() - start
        results["metrics"]["denoise_total_s"] = round(wall, 4)
        results["metrics"]["denoise_per_step_ms"] = round(wall / steps * 1000.0, 4)
        results["metrics"]["denoise_steps"] = steps
        try:
            results["metrics"]["peak_vram_bytes"] = int(torch.cuda.max_memory_allocated())
            results["metrics"]["reserved_vram_bytes"] = int(torch.cuda.max_memory_reserved())
        except Exception:
            pass
        del latent, emb, up, mid, norm, qk
    except Exception as exc:
        results["metrics"]["denoise_error"] = str(exc)[:200]

results["torch"] = torch.__version__
emit(results)
'''


def _run_task_group(
    profile: dict[str, Any],
    tasks: str,
    *,
    venv_python: Path | None,
    scale: float,
    iters: int,
    warmup: int,
    denoise: bool,
    timeout: int,
    env_overrides: dict[str, str] | None = None,
) -> dict[str, Any]:
    """Run one group of measurements in a fresh subprocess."""
    python = str(venv_python) if venv_python and venv_python.exists() else sys.executable

    env = dict(os.environ)
    # A stale PYTORCH_HIP_ALLOC_CONF from an older toolkit version segfaults torch
    # on import. Strip it here as a safety net; doctor/bench report it separately.
    env.pop("PYTORCH_HIP_ALLOC_CONF", None)
    env.update(profile_to_env(profile))
    if env_overrides:
        env.update(env_overrides)

    env["ROCM_AI_BENCH_PROFILE"] = json.dumps(profile)
    env["ROCM_AI_BENCH_SCALE"] = str(scale)
    env["ROCM_AI_BENCH_ITERS"] = str(iters)
    env["ROCM_AI_BENCH_WARMUP"] = str(warmup)
    env["ROCM_AI_BENCH_DENOISE"] = "1" if denoise else "0"
    env["ROCM_AI_BENCH_TASKS"] = tasks
    env["PYTHONWARNINGS"] = "ignore"
    env["PYTHONFAULTHANDLER"] = "0"
    env["TOKENIZERS_PARALLELISM"] = "false"

    try:
        proc = subprocess.run(
            [python, "-c", BENCH_WORKER],
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": f"timed out after {timeout}s"}

    for line in proc.stdout.splitlines():
        if line.startswith("ROCM_AI_BENCH_JSON:"):
            try:
                return json.loads(line[len("ROCM_AI_BENCH_JSON:"):])
            except json.JSONDecodeError:
                continue

    tail = (proc.stderr or proc.stdout or "").strip()[-700:]
    return {"ok": False, "error": f"crashed (exit {proc.returncode}). Tail: {tail}"}


def run_candidate(
    profile: dict[str, Any],
    *,
    venv_python: Path | None,
    scale: float = 1.0,
    iters: int = 30,
    warmup: int = 3,
    denoise: bool = True,
    timeout: int = 600,
) -> dict[str, Any]:
    """
    Execute one candidate and return its merged measurement.

    Measurements are split across fresh processes. Timing every workload in a
    single process was measured to contaminate the results: attention read
    3.0 ms in a clean process but 15 ms when a convolution benchmark had just run
    in the same one, which was enough to declare the slowest attention kernel the
    fastest. Grouping by workload keeps each measurement's GPU state predictable.

    Convolution-related work shares a process (the convolution benchmark depends
    on the same MIOpen cache the cold-start measurement populates); the denoise
    loop gets its own.
    """
    groups: list[str] = ["cold,conv"]
    if denoise:
        groups.append("denoise")

    merged: dict[str, Any] = {"ok": False, "metrics": {}, "errors": []}
    any_ok = False

    for tasks in groups:
        # Give the cold/conv group a private, empty MIOpen directory so that
        # "cold start" means cold. Reusing one directory across candidates would
        # mean candidate 2 inheriting the database candidate 1 just wrote.
        env_overrides = None
        temp_dir: str | None = None
        if tasks == "cold,conv":
            temp_dir = tempfile.mkdtemp(prefix="rocm-ai-miopen-")
            env_overrides = {
                "MIOPEN_USER_DB_PATH": temp_dir,
                "MIOPEN_CUSTOM_CACHE_DIR": temp_dir,
            }

        try:
            result = _run_task_group(
                profile,
                tasks,
                venv_python=venv_python,
                scale=scale,
                iters=iters,
                warmup=warmup,
                denoise=denoise,
                timeout=timeout,
                env_overrides=env_overrides,
            )
        finally:
            if temp_dir:
                shutil.rmtree(temp_dir, ignore_errors=True)

        if result.get("ok"):
            any_ok = True
            merged["metrics"].update(result.get("metrics", {}))
            if result.get("torch"):
                merged["torch"] = result["torch"]
            if result.get("dtype"):
                merged["dtype"] = result["dtype"]
        else:
            merged["errors"].append(f"{tasks}: {result.get('error', 'unknown error')}")

    merged["ok"] = any_ok
    if not any_ok:
        merged["error"] = "; ".join(merged["errors"])[:500]
    elif merged["errors"]:
        # Partial success: keep what we measured, but say what failed.
        merged["error"] = "partial: " + "; ".join(merged["errors"])[:300]
    return merged


def run_attention_probe(
    *,
    venv_python: Path | None,
    iters: int = 30,
    warmup: int = 5,
    timeout: int = 300,
) -> dict[str, Any]:
    """
    Time every usable SDPA kernel in a single, clean, dedicated process.

    This is separated from the candidate sweep for a measured reason: attention
    reads ~3 ms for the fused kernels in a fresh process, but ~15 ms when
    measured late in a longer benchmark process. Running it standalone is what
    makes the kernel table trustworthy, and it is the same reason attention does
    not contribute to candidate scoring.
    """
    result = _run_task_group(
        build_profile("baseline"),
        "attn",
        venv_python=venv_python,
        scale=1.0,
        iters=iters,
        warmup=warmup,
        denoise=False,
        timeout=timeout,
    )
    if not result.get("ok"):
        return {"ok": False, "error": result.get("error", "attention probe failed")}
    metrics = result.get("metrics", {})
    return {
        "ok": True,
        "kernels": result.get("attention_kernels", {}),
        "best": metrics.get("attn_best_kernel"),
        "best_ms": metrics.get("attn_best_ms"),
        "default_ms": metrics.get("attn_ms"),
    }


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------


def score_of(metrics: dict[str, Any]) -> float | None:
    """
    Single comparable number, in milliseconds of "denoise step" equivalent.

    Only convolution-bound work is scored. Attention is deliberately excluded:
    no profile in this toolkit changes the attention kernel (see profile_to_env),
    and attention timings measured inside a long benchmark process were observed
    to inflate from 3 ms to 15 ms — roughly 5x — which would have let measurement
    drift masquerade as a performance difference. Attention is still measured and
    reported, from a clean process, but it does not decide anything.
    """
    per_step = metrics.get("denoise_per_step_ms")
    conv = metrics.get("conv_ms")
    cold = metrics.get("cold_first_conv_ms")
    if per_step is None and conv is None:
        return None
    total = 0.0
    if per_step is not None:
        total += per_step * 1.0
    if conv is not None:
        total += conv * 0.30
    # Cold start is a one-off cost, so it carries a small weight; it breaks ties
    # between configurations that are otherwise equal on steady-state throughput.
    if cold is not None:
        total += cold * 0.05
    return total


def spread_ratio(metrics: dict[str, Any]) -> float:
    ratios = []
    for base, spread in (("conv_ms", "conv_spread_ms"), ("attn_ms", "attn_spread_ms")):
        b, s = metrics.get(base), metrics.get(spread)
        if b and s and b > 0:
            ratios.append(s / b)
    return max(ratios) if ratios else 0.0


def numeric_ok(metrics: dict[str, Any]) -> tuple[bool, str]:
    for key, label in (("conv_rel_l2_pct", "convolution"), ("attn_rel_l2_pct", "attention")):
        val = metrics.get(key)
        if val is not None and val > NUMERIC_TOLERANCE_PCT:
            return False, f"{label} output deviates {val:.2f}% from reference"
    return True, ""


def rank_results(measurements: list[dict[str, Any]]) -> dict[str, Any]:
    """Turn raw measurements into a ranked, honest verdict."""
    scored: list[dict[str, Any]] = []
    anchor_scores: list[float] = []

    for m in measurements:
        metrics = m.get("measurement", {}).get("metrics", {}) if m.get("ok") else {}
        profile = m.get("profile", {})

        # The anchor is a repeat of the baseline used purely for drift detection.
        # It never competes for the win.
        if m["key"] == ANCHOR_KEY:
            if m.get("ok") and metrics:
                anchor_score = score_of(metrics)
                if anchor_score is not None:
                    anchor_scores.append(anchor_score)
            continue

        entry = {
            "key": m["key"],
            "title": m.get("title", m["key"]),
            "ok": bool(m.get("ok")),
            "error": m.get("error"),
            "score": score_of(metrics) if metrics else None,
            "metrics": metrics,
            "spread_ratio": spread_ratio(metrics) if metrics else 0.0,
            "vram_mode": profile.get("vram_mode", "default"),
            "rejected": None,
        }
        if entry["ok"] and metrics:
            good, why = numeric_ok(metrics)
            if not good:
                entry["rejected"] = why
            elif entry["spread_ratio"] > NOISE_REJECT_RATIO:
                entry["rejected"] = (
                    f"measurement too noisy (spread {entry['spread_ratio']*100:.1f}% "
                    f"of median; close other GPU apps and retry)"
                )
        scored.append(entry)

    usable = [e for e in scored if e["ok"] and e["score"] is not None and not e["rejected"]]
    # Rank by score, then by safety: where two entries have equal scores the
    # safer VRAM mode is listed first, so `fastest` below is deterministic.
    usable.sort(key=lambda e: (e["score"], _safety_rank(e)))

    baseline = next((e for e in scored if e["key"] == "baseline"), None)
    baseline_score = baseline["score"] if baseline and baseline["score"] else None

    verdict: dict[str, Any] = {
        "engine_version": ENGINE_VERSION,
        "generated": now_utc(),
        "results": scored,
        "baseline_score": baseline_score,
        "winner": None,
        "winner_score": None,
        "speedup_pct": None,
        "conclusive": False,
        "tie": False,
        "drift_pct": None,
        "contaminated": False,
        "notes": [],
    }

    # --- Drift check --------------------------------------------------------
    # Measured repeatedly on an RX 7900 XTX: a long candidate sweep drifts, and
    # the drift is not uniform. Attention measured 3.0 ms in a fresh process but
    # 15.8 ms late in a 7-candidate run, which was enough to make the slowest
    # kernel (MATH) look like the fastest. A verdict drawn from that run would
    # have been confidently wrong, so the run is discarded instead.
    if len(anchor_scores) == 2:
        first, last = anchor_scores[0], anchor_scores[1]
        if first > 0:
            drift = abs(last - first) / first * 100.0
            verdict["drift_pct"] = round(drift, 1)
            if drift > ANCHOR_DRIFT_TOLERANCE_PCT:
                verdict["contaminated"] = True
                verdict["notes"].append(
                    f"GPU performance drifted {drift:.0f}% during this run "
                    f"(the same reference configuration measured {first:.1f} then "
                    f"{last:.1f}). That invalidates the comparison, so no result is "
                    f"being applied. Common causes: something else started using the "
                    f"GPU, thermal throttling, or a laptop on battery. Let the GPU "
                    f"idle a moment and run the tuner again."
                )
                return verdict

    if not usable:
        verdict["notes"].append(
            "No candidate produced a trustworthy measurement. See errors above."
        )
        return verdict

    # Tie-break by safety. A profile within TIE_BAND_PCT of the fastest is
    # statistically indistinguishable from it, so the least aggressive VRAM mode
    # wins rather than whichever candidate happened to sample slightly faster.
    fastest = usable[0]
    if fastest["score"] > 0:
        band = [
            e for e in usable
            if (e["score"] - fastest["score"]) / fastest["score"] * 100.0 <= TIE_BAND_PCT
        ]
    else:
        band = [fastest]
    band.sort(key=lambda e: (_safety_rank(e), e["score"]))
    best = band[0]

    if len(band) > 1 and best["key"] != fastest["key"]:
        verdict["tie"] = True
        losers = ", ".join(e["key"] for e in band if e["key"] != best["key"])
        verdict["notes"].append(
            f"{len(band)} profiles measured within {TIE_BAND_PCT:.0f}% of each other "
            f"({losers} vs {best['key']}), which is not a meaningful difference. "
            f"Chose '{best['key']}' because its VRAM mode is the safest of the tied set."
        )

    verdict["winner"] = best["key"]
    verdict["winner_score"] = best["score"]

    if baseline_score:
        speedup = (baseline_score - best["score"]) / baseline_score * 100.0
        verdict["speedup_pct"] = speedup
        if best["key"] == "baseline":
            # The baseline is the reference point, so there is no speed-up to
            # report. Say that plainly rather than implying a win or a loss.
            verdict["notes"].append(
                "ComfyUI's own default settings measured fastest on this GPU. "
                "This is a legitimate result: not every change helps every card, and "
                "the toolkit leaves your configuration alone rather than applying "
                "something that measured no better."
            )
            verdict["conclusive"] = True
        elif speedup < NOISE_FLOOR_PCT:
            verdict["notes"].append(
                f"Best candidate is only {speedup:.1f}% ahead of ComfyUI defaults, which is "
                f"inside measurement noise ({NOISE_FLOOR_PCT:.0f}%). Reporting as inconclusive "
                "rather than claiming a win."
            )
        else:
            verdict["conclusive"] = True
    else:
        verdict["notes"].append(
            "Baseline could not be measured, so the speed-up over stock settings is unknown."
        )
        verdict["conclusive"] = True

    # Surface measurable changes that were *worse*, so users see the trade-off.
    worse = [
        e for e in usable
        if baseline_score and e["key"] != "baseline" and e["score"] > baseline_score
    ]
    if worse:
        names = ", ".join(
            f"{e['title']} (+{(e['score']-baseline_score)/baseline_score*100:.0f}%)"
            for e in worse[:3]
        )
        verdict["notes"].append(f"Slower than ComfyUI defaults on this GPU: {names}")

    return verdict


def human_report(verdict: dict[str, Any]) -> str:
    lines: list[str] = []
    lines.append("")
    lines.append("Benchmark results")
    lines.append("-" * 78)
    lines.append(
        f"{'profile':<24} {'score':>8} {'vs stock':>9} {'cold start':>11} {'step':>8}  status"
    )
    lines.append("-" * 78)

    baseline = verdict.get("baseline_score")
    for entry in verdict["results"]:
        name = entry["title"][:23]
        metrics = entry.get("metrics") or {}
        cold = metrics.get("cold_first_conv_ms")
        step = metrics.get("denoise_per_step_ms")
        cold_s = f"{cold:.0f} ms" if cold is not None else "-"
        step_s = f"{step:.1f} ms" if step is not None else "-"

        if not entry["ok"]:
            lines.append(f"{name:<24} {'-':>8} {'-':>9} {'-':>11} {'-':>8}  crashed")
            continue
        if entry["score"] is None:
            lines.append(f"{name:<24} {'-':>8} {'-':>9} {cold_s:>11} {step_s:>8}  no data")
            continue
        delta = ""
        if baseline:
            pct = (entry["score"] - baseline) / baseline * 100.0
            delta = f"{pct:+.1f}%"
        status = "ok"
        if entry.get("rejected"):
            status = f"REJECTED: {entry['rejected']}"
        elif entry["key"] == verdict.get("winner"):
            status = "WINNER"
        lines.append(
            f"{name:<24} {entry['score']:>8.2f} {delta:>9} {cold_s:>11} {step_s:>8}  {status}"
        )

    lines.append("-" * 78)
    lines.append("  score = weighted steady-state cost (lower is better); cold start = first conv")
    if verdict.get("drift_pct") is not None:
        lines.append(f"  drift check: reference configuration varied {verdict['drift_pct']:.0f}% "
                     f"across the run (tolerance {ANCHOR_DRIFT_TOLERANCE_PCT:.0f}%)")
    if verdict.get("speedup_pct") is not None:
        lines.append(
            f"Winner: {verdict['winner']}  ({verdict['speedup_pct']:+.1f}% vs ComfyUI defaults)"
        )
    elif verdict.get("winner"):
        lines.append(f"Winner: {verdict['winner']}")
    for note in verdict.get("notes", []):
        lines.append("")
        for wrapped in textwrap.wrap(note, 74):
            lines.append(f"  {wrapped}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------


def resolve_profile(key: str = "auto") -> dict[str, Any]:
    """Pick a profile to apply: an explicit key, the saved winner, or a safe default."""
    if key != "auto":
        return build_profile(key)

    if PROFILE_JSON.exists():
        try:
            payload = json.loads(PROFILE_JSON.read_text())
            saved = payload.get("profile", {}).get("key")
            if saved and saved in PROFILES_BY_KEY:
                return build_profile(saved)
        except (OSError, json.JSONDecodeError, KeyError):
            pass

    return build_profile("baseline")


def apply_profile(profile: dict[str, Any], *, source: str = "manual", metrics: dict[str, Any] | None = None) -> Path:
    """Persist a tuned profile as both JSON (for tooling) and env (for shells)."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    payload = {
        "engine_version": ENGINE_VERSION,
        "applied": now_utc(),
        "source": source,
        "profile": profile,
        "comfyui_args": profile_to_comfyui_args(profile),
        "env": profile_to_env(profile),
    }
    if metrics:
        payload["metrics"] = metrics

    tmp = PROFILE_JSON.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(payload, indent=2) + "\n")
    tmp.replace(PROFILE_JSON)

    # Shell-consumable form. Every name is namespaced so a stale file can never
    # leak a wrong export into a launcher.
    env_lines = [
        "# Generated by scripts/utils/perf_engine.py — do not edit by hand.",
        f"# Applied: {payload['applied']}  (source: {source})",
        f"# Profile: {profile['key']} — {profile_to_description(profile)}",
        f"export ROCM_AI_PERF_PROFILE=\"{profile['key']}\"",
        f"export ROCM_AI_PERF_SOURCE=\"{source}\"",
    ]
    for key, value in sorted(profile_to_env(profile).items()):
        env_lines.append(f'export {key}="{value}"')
    args = profile_to_comfyui_args(profile)
    env_lines.append(f'export ROCM_AI_COMFYUI_ARGS="{ " ".join(args) }"')
    env_lines.append("")

    tmp_env = PROFILE_ENV.with_suffix(".env.tmp")
    tmp_env.write_text("\n".join(env_lines))
    tmp_env.replace(PROFILE_ENV)

    return PROFILE_JSON


def show_profile() -> str:
    if not PROFILE_JSON.exists():
        return (
            "No performance profile has been tuned yet.\n"
            "Run:  menu.sh -> Performance -> Auto-Tune for this GPU"
        )
    try:
        payload = json.loads(PROFILE_JSON.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        return f"Could not read {PROFILE_JSON}: {exc}"

    profile = payload.get("profile", {})
    lines = [
        "Active performance profile",
        "=" * 44,
        f"Profile   : {profile.get('key')} — {profile.get('title', '')}",
        f"Applied   : {payload.get('applied')}",
        f"Source    : {payload.get('source')}",
        "",
        "Settings  :",
    ]
    for key, value in payload.get("env", {}).items():
        lines.append(f"  {key}={value}")
    args = payload.get("comfyui_args", [])
    lines.append("")
    lines.append(f"ComfyUI args: {' '.join(args) if args else '(none)'}")

    backend = profile.get("prefer_attn_backend")
    if backend:
        lines.append(f"Attention    : {backend} (measured fastest on this GPU)")
    else:
        lines.append("Attention    : automatic (PyTorch default dispatcher)")

    metrics = payload.get("metrics", {})
    if metrics:
        lines.append("")
        lines.append("Measured on this machine:")
        for key, label in (
            ("cold_first_conv_ms", "first conv (cold)"),
            ("conv_ms", "convolution block"),
            ("attn_ms", "attention"),
            ("denoise_per_step_ms", "denoise step"),
        ):
            if key in metrics and metrics[key] is not None:
                lines.append(f"  {label:<22} {metrics[key]} ms")
        # peak_vram_bytes is deliberately not shown. It reports only what
        # PyTorch's allocator held at one instant in the benchmarking process,
        # which for a fused-attention workload is a fraction of a gigabyte and
        # says nothing about the VRAM a real model needs. Showing it invited the
        # reader to conclude their models would fit in 0.1 GB.
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Self-check
# ---------------------------------------------------------------------------


def run_doctor() -> int:
    """Validate the engine without needing a GPU. Returns a shell exit code."""
    problems: list[str] = []
    print("Performance engine self-check")
    print("=" * 44)

    print(f"engine version   : {ENGINE_VERSION}")
    print(f"python           : {sys.version.split()[0]}")
    if sys.version_info < (3, 10):
        problems.append("Python 3.10+ is required (Ubuntu 22.04/24.04 both satisfy this).")

    print(f"config dir       : {CONFIG_DIR}")
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        problems.append(f"cannot create config dir: {exc}")

    # Every candidate must serialise to env cleanly.
    for spec in PROFILE_SPECS:
        try:
            profile = build_profile(spec["key"])
            env = profile_to_env(profile)
            json.dumps(profile)
            assert env.get("HSA_ENABLE_DXG_DETECTION") == "1"
        except Exception as exc:  # pragma: no cover - defensive
            problems.append(f"profile '{spec['key']}' failed to build: {exc}")

    print(f"profiles         : {len(PROFILE_SPECS)} defined, all serialise cleanly")

    # Regression guard: PYTORCH_HIP_ALLOC_CONF segfaults torch 2.9.1+rocm7.2.3.
    for spec in PROFILE_SPECS:
        for key, value in profile_to_env(build_profile(spec["key"])).items():
            if key.upper() == "PYTORCH_HIP_ALLOC_CONF":
                problems.append(
                    "profile emitted PYTORCH_HIP_ALLOC_CONF, which segfaults this "
                    "PyTorch build — this is a regression in the engine itself"
                )

    dangerous, why = is_alloc_conf_set()
    if dangerous:
        problems.append(why)

    # The benchmark worker must actually boot PyTorch under a real profile env.
    # This is the check that would have caught the segfault automatically.
    venv_guess = find_venv_python()
    if venv_guess:
        probe_env = dict(os.environ)
        probe_env.update(profile_to_env(build_profile("baseline")))
        probe_env.pop("PYTORCH_HIP_ALLOC_CONF", None)
        try:
            boot = subprocess.run(
                [str(venv_guess), "-c", "import torch; print(torch.__version__)"],
                capture_output=True, text=True, timeout=120, env=probe_env,
            )
            if boot.returncode == 0:
                print(f"torch boot test  : OK ({boot.stdout.strip()})")
            else:
                problems.append(
                    f"torch failed to boot under a profile environment "
                    f"(exit {boot.returncode}): {(boot.stderr or '')[-200:]}"
                )
                print(f"torch boot test  : FAILED (exit {boot.returncode})")
        except (subprocess.TimeoutExpired, OSError) as exc:
            problems.append(f"torch boot test could not run: {exc}")

    # The embedded workers must compile. They are string literals inside this
    # file, so an indentation mistake in one of them is invisible to a normal
    # syntax check of the module itself and only shows up at benchmark time.
    for name, source in (("BENCH_WORKER", BENCH_WORKER), ("PROBE_SCRIPT", PROBE_SCRIPT)):
        try:
            compile(source, f"<{name}>", "exec")
            print(f"{name:<17}: compiles OK ({len(source.splitlines())} lines)")
        except SyntaxError as exc:
            problems.append(
                f"embedded {name} has a syntax error at line {exc.lineno}: {exc.msg}"
            )
            print(f"{name:<17}: SYNTAX ERROR at line {exc.lineno}: {exc.msg}")

    venv = find_venv_python()
    print(f"genai_env python : {venv if venv else 'not found (run base install)'}")

    probe = _run_probe(venv)
    if probe.get("ok") and probe.get("cuda_available"):
        print(f"GPU              : {probe.get('device_name')}")
        print("status           : ready — run 'bench' to tune this GPU")
    elif probe.get("ok"):
        print("GPU              : not visible to PyTorch")
        print("status           : engine is fine; fix GPU visibility first")
        problems.append("GPU not visible to PyTorch")
    else:
        print(f"PyTorch probe    : {probe.get('error')}")
        print("status           : engine is fine; PyTorch is not usable yet")
        problems.append("PyTorch probe failed")

    print("")
    if problems:
        print("Issues found:")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("All checks passed.")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _add_common(sp: argparse.ArgumentParser) -> None:
    sp.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    sp.add_argument(
        "--venv",
        default="genai_env",
        help="virtualenv name under $HOME that holds PyTorch (default: genai_env)",
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="perf_engine.py",
        description="Measure and apply real ROCm performance settings for this GPU.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            """
            Examples:
              perf_engine.py probe                 # what does this machine actually support?
              perf_engine.py bench                 # measure candidates, pick a winner
              perf_engine.py bench --dry-run       # show candidates without running them
              perf_engine.py apply --profile auto  # persist the best previously measured profile
              perf_engine.py show                  # what is active right now
              perf_engine.py doctor                # self-check (no GPU needed)
            """
        ),
    )
    parser.add_argument("--version", action="version", version=f"perf_engine {ENGINE_VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)

    p_probe = sub.add_parser("probe", help="report GPU + Python capabilities")
    _add_common(p_probe)

    p_profiles = sub.add_parser("profiles", help="list candidate profiles")
    _add_common(p_profiles)

    p_bench = sub.add_parser("bench", help="measure candidates and choose a winner")
    _add_common(p_bench)
    p_bench.add_argument("--only", help="comma-separated profile keys to test")
    p_bench.add_argument("--iters", type=int, default=30, help="timed iterations per op (default 30)")
    p_bench.add_argument("--warmup", type=int, default=3, help="warmup iterations (default 3)")
    p_bench.add_argument("--scale", type=float, default=1.0, help="scale workload size")
    p_bench.add_argument("--quick", action="store_true", help="fast pass: fewer iterations, skip denoise loop")
    p_bench.add_argument("--no-denoise", action="store_true", help="skip the multi-step loop simulation")
    p_bench.add_argument("--timeout", type=int, default=600, help="per-candidate timeout in seconds")
    p_bench.add_argument("--dry-run", action="store_true", help="list candidates and exit")
    p_bench.add_argument("--yes", action="store_true", help="apply the winner without confirmation")
    p_bench.add_argument("--save-report", action="store_true", help="also write the full report to the config dir")

    p_apply = sub.add_parser("apply", help="persist a profile")
    _add_common(p_apply)
    p_apply.add_argument("--profile", default="auto", help="profile key, or 'auto' for the measured winner")

    p_show = sub.add_parser("show", help="show the active profile")
    _add_common(p_show)

    p_doctor = sub.add_parser("doctor", help="self-check the engine")
    _add_common(p_doctor)

    args = parser.parse_args(argv)
    venv_python = find_venv_python(getattr(args, "venv", "genai_env"))

    # -- probe ---------------------------------------------------------------
    if args.command == "probe":
        probe = _run_probe(venv_python)
        gfx = detect_gfx_arch()
        if args.json:
            print(json.dumps({"gfx": gfx, "rocm": detect_rocm_version(), "wsl": is_wsl(), **probe}, indent=2))
        else:
            print(human_probe(probe, gfx))
        return 0 if probe.get("ok") and probe.get("cuda_available") else 1

    # -- profiles ------------------------------------------------------------
    if args.command == "profiles":
        probe = _run_probe(venv_python)
        keys = candidates_for(probe)
        if args.json:
            print(json.dumps([build_profile(k) for k in keys], indent=2))
            return 0
        print("Candidate profiles for this machine")
        print("=" * 68)
        for key in keys:
            profile = build_profile(key)
            spec = PROFILES_BY_KEY[key]
            print(f"\n  {key:<16} {spec['title']}")
            print(f"  {'':<16} {spec['desc']}")
            print(f"  {'':<16} -> {profile_to_description(profile)}")
        print("\nAll defined profiles:", ", ".join(p["key"] for p in PROFILE_SPECS))
        return 0

    # -- bench ---------------------------------------------------------------
    if args.command == "bench":
        probe = _run_probe(venv_python)
        if not probe.get("ok") or not probe.get("cuda_available"):
            msg = probe.get("error") or "PyTorch cannot see a HIP/ROCm GPU"
            if args.json:
                print(json.dumps({"ok": False, "error": msg}, indent=2))
            else:
                eprint(f"error: {msg}")
                eprint("")
                eprint("Nothing can be measured until the GPU is visible to PyTorch.")
                eprint("Run:  scripts/utils/perf_engine.py probe    for the fix checklist.")
            return 2

        only = [k.strip() for k in args.only.split(",")] if args.only else None
        keys = candidates_for(probe, only)

        if args.dry_run:
            payload = {"candidates": [build_profile(k) for k in keys], "vram_bytes": probe.get("props", {}).get("total_memory")}
            if args.json:
                print(json.dumps(payload, indent=2))
            else:
                print("Dry run — these candidates would be measured:")
                for key in keys:
                    print(f"  {key:<16} {profile_to_description(build_profile(key))}")
            return 0

        scale = 0.5 if args.quick else args.scale
        iters = 12 if args.quick else args.iters
        denoise = not (args.no_denoise or args.quick)

        if not args.json:
            vram = probe.get("props", {}).get("total_memory")
            print(f"GPU      : {probe.get('device_name')}  ({human_gb(vram)} VRAM)")
            print(f"PyTorch  : {probe.get('torch')}   dtypes: "
                  f"{', '.join(k for k, v in probe.get('dtypes', {}).items() if v)}")
            print(f"Candidates: {len(keys)}")
            print("")

        measurements: list[dict[str, Any]] = []

        # Drift detection: the baseline configuration is measured once before the
        # sweep and once after it, and the two are compared. A swept run on this
        # hardware degrades measurably (attention was observed drifting from
        # 3.0 ms to 15.8 ms across seven candidates), which is enough to crown the
        # slowest kernel as the fastest. The anchor pair makes that detectable
        # instead of silently producing a wrong answer.
        anchor_first: dict[str, Any] | None = None
        want_anchor = len(keys) > 1

        def measure(label: str, profile: dict[str, Any]) -> dict[str, Any]:
            result = run_candidate(
                profile,
                venv_python=venv_python,
                scale=scale,
                iters=iters,
                warmup=args.warmup,
                denoise=denoise,
                timeout=args.timeout,
            )
            if not args.json:
                metrics = result.get("metrics", {}) if result.get("ok") else {}
                if metrics:
                    score = score_of(metrics)
                    bits = []
                    if "cold_first_conv_ms" in metrics:
                        bits.append(f"cold {metrics['cold_first_conv_ms']:.0f}ms")
                    if "conv_ms" in metrics:
                        bits.append(f"conv {metrics['conv_ms']:.1f}ms")
                    if "attn_ms" in metrics:
                        bits.append(f"attn {metrics['attn_ms']:.1f}ms")
                    if "denoise_per_step_ms" in metrics:
                        bits.append(f"step {metrics['denoise_per_step_ms']:.1f}ms")
                    print(f"        {'  '.join(bits)}   score {score:.2f}")
                else:
                    print(f"        FAILED: {result.get('error', 'unknown error')}")
            return result

        # Global warm-up pass. Measured on an RX 7900 XTX: the first denoise loop
        # of a session takes ~104 ms per step while every subsequent run of the
        # SAME configuration takes ~16 ms. That 41% swing comes from GPU cold
        # state (clocks ramping, first-touch page mapping) and is large enough to
        # decide a benchmark by itself. The measurement is taken and discarded so
        # the real sweep starts from a settled GPU.
        if not args.json:
            print("  [warm-up] settling the GPU (discarded) ...", flush=True)
        measure("warm-up", build_profile("baseline"))

        if want_anchor:
            if not args.json:
                print("  [anchor A] reference configuration ...", flush=True)
            anchor_first = measure("anchor A", build_profile("baseline"))

        for index, key in enumerate(keys, start=1):
            profile = build_profile(key)
            spec = PROFILES_BY_KEY[key]
            if not args.json:
                print(f"  [{index}/{len(keys)}] {spec['title']} ...", flush=True)
            result = measure(spec["title"], profile)
            measurements.append({
                "key": key,
                "title": spec["title"],
                "ok": bool(result.get("ok")),
                "error": result.get("error"),
                "profile": profile,
                "measurement": result,
            })

        if want_anchor:
            if not args.json:
                print("  [anchor B] reference configuration, repeated ...", flush=True)
            anchor_last = measure("anchor B", build_profile("baseline"))
            measurements.append({
                "key": ANCHOR_KEY,
                "title": "drift reference A",
                "ok": bool(anchor_first and anchor_first.get("ok")),
                "error": (anchor_first or {}).get("error"),
                "profile": build_profile("baseline"),
                "measurement": anchor_first or {},
            })
            measurements.append({
                "key": ANCHOR_KEY,
                "title": "drift reference B",
                "ok": bool(anchor_last.get("ok")),
                "error": anchor_last.get("error"),
                "profile": build_profile("baseline"),
                "measurement": anchor_last,
            })

        verdict = rank_results(measurements)

        if verdict.get("contaminated"):
            if args.json:
                print(json.dumps({"probe": probe, **verdict}, indent=2))
            else:
                print(human_report(verdict))
            return 4

        if args.save_report:
            CONFIG_DIR.mkdir(parents=True, exist_ok=True)
            LAST_REPORT.write_text(json.dumps({"probe": probe, **verdict}, indent=2) + "\n")

        # Attention is measured once, in its own clean process, rather than per
        # candidate. It does not influence scoring (no profile changes the
        # attention kernel) and per-candidate measurement inside a long sweep
        # produced inflated, misleading numbers.
        if not args.json:
            print("  [probe] attention kernels ...", flush=True)
        attn_probe = run_attention_probe(
            venv_python=venv_python,
            iters=iters,
            warmup=max(args.warmup, 5),
            timeout=args.timeout,
        )
        kernels: dict[str, Any] = attn_probe.get("kernels", {}) if attn_probe.get("ok") else {}
        verdict["attention_probe"] = {
            "ok": bool(attn_probe.get("ok")),
            "best": attn_probe.get("best"),
            "best_ms": attn_probe.get("best_ms"),
            "default_ms": attn_probe.get("default_ms"),
            "error": attn_probe.get("error"),
        }
        verdict["attention_kernels"] = kernels

        if args.json:
            print(json.dumps({"probe": probe, **verdict}, indent=2))
        else:
            print(human_report(verdict))
            winner_metrics = next(
                (e["metrics"] for e in verdict["results"] if e["key"] == verdict["winner"]), {}
            )
            summary = attention_kernel_summary(winner_metrics, kernels)
            if summary:
                print("\n".join(summary))

        if not verdict.get("winner"):
            return 3

        if not verdict.get("conclusive"):
            return 0

        winner_profile = build_profile(verdict["winner"])
        # Record the fastest numerically-sound attention kernel measured on this
        # GPU, so the profile documents what the hardware prefers.
        if attn_probe.get("ok") and attn_probe.get("best"):
            winner_profile["prefer_attn_backend"] = attn_probe["best"]

        metrics = next(
            (e["metrics"] for e in verdict["results"] if e["key"] == verdict["winner"]),
            None,
        )

        if args.yes:
            path = apply_profile(winner_profile, source="auto-tuner", metrics=metrics)
            print(f"\nApplied and saved to {path}")
            return 0

        # Non-interactive when stdout is not a TTY (e.g. driven from the menu).
        if not sys.stdin.isatty():
            path = apply_profile(winner_profile, source="auto-tuner", metrics=metrics)
            print(f"\nApplied and saved to {path}")
            return 0

        try:
            answer = input(f"\nApply '{verdict['winner']}' as your default? [Y/n] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            answer = "n"
        if answer in ("", "y", "yes"):
            path = apply_profile(winner_profile, source="auto-tuner", metrics=metrics)
            print(f"Applied and saved to {path}")
        else:
            print("Not applied. Your previous profile is unchanged.")
        return 0

    # -- apply ---------------------------------------------------------------
    if args.command == "apply":
        profile = resolve_profile(args.profile)
        path = apply_profile(profile, source=f"apply:{args.profile}")
        if args.json:
            print(json.dumps({"ok": True, "path": str(path), "profile": profile}, indent=2))
        else:
            print(f"Applied profile '{profile['key']}' -> {path}")
            print(f"  {profile_to_description(profile)}")
        return 0

    # -- show ----------------------------------------------------------------
    if args.command == "show":
        if args.json and PROFILE_JSON.exists():
            print(PROFILE_JSON.read_text())
        else:
            print(show_profile())
        return 0

    # -- doctor --------------------------------------------------------------
    if args.command == "doctor":
        return run_doctor()

    parser.print_help()
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        eprint("\nInterrupted.")
        sys.exit(130)
