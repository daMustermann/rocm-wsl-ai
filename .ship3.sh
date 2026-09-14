#!/bin/bash
set -uo pipefail
SRC=/mnt/f/Coding/rocm-wsl-ai-2
DST="$HOME/rocm-wsl-ai"
export PATH="$HOME/.local/bin:$PATH"

cd "$SRC" || exit 1
rm -f .logcheck.sh .tritontest.sh .cleanupcuda.sh .nvwhere.sh .nvorigin.sh
rm -rf scripts/utils/__pycache__
git add -A
echo "=== staged ==="
git status --short | sed 's/^/  /'

git commit -q -F - <<'MSG'
Document ComfyUI-Manager's interaction with the venv, and COMFYUI_EXTRA_ARGS

A ComfyUI-Manager dependency install restarted ComfyUI and the startup log
prompted a check for CUDA contamination, so this records what was actually
measured and gives the script a documented extension point.

Findings on a real installation:

  * The environment was NOT contaminated. 15 nvidia-* CUDA packages were present
    on the machine, but in the user site-packages at
    ~/.local/lib/python3.10/site-packages, which is not on the venv's sys.path.
    Inside the venv `pip list` reported zero, and `import nvidia.cublas` failed.
    The venv isolates the toolkit from stray packages elsewhere, by design.
  * torch and triton were untouched by the Manager restart:
    2.10.0+rocm7.2.4 and 3.6.0+rocm7.2.4, GPU visible.
  * The real risk remains that Manager resolves requirements with plain pip and
    does not strip torch, so it can replace the ROCm build with the CUDA one. The
    troubleshooting notes now cover how to detect and repair that.

Also: scripts/start/comfyui.sh gains a COMFYUI_EXTRA_ARGS hook, and documents why
ComfyUI 0.35's --enable-triton-backend is left off. It does activate here
("Found triton 3.6.0+rocm7.2.4. Enabling comfy-kitchen triton backend"), but its
reported capability list adds nothing the hip backend lacks, and the only timings
available were confounded by page cache. Enabling it by default would be an
unmeasured change, so the flag is opt-in and the doc says how to A/B it.
MSG

echo
echo "=== commit ==="
git log --oneline -1 | sed 's/^/  /'
echo "  $(git show --stat --format='' HEAD | tail -1)"

echo
echo "=== push ==="
git push origin main 2>&1 | tail -2 | sed 's/^/  /'
git fetch origin --quiet 2>/dev/null
echo "  local $(git rev-parse --short HEAD) / remote $(git rev-parse --short origin/main)"

echo
echo "=== deploy ==="
cd "$DST" || exit 1
git fetch origin --quiet 2>/dev/null
git reset --hard origin/main 2>&1 | tail -1 | sed 's/^/  /'
echo "  HEAD: $(git rev-parse --short HEAD)  clean: $( [ -z "$(git status --porcelain)" ] && echo yes || echo no )"

echo
echo "=== syntax pass ==="
fail=0
while IFS= read -r f; do
    bash -n "$f" 2>/tmp/e || { echo "  FAIL $f"; cat /tmp/e; fail=1; }
done < <(find "$DST" -name '*.sh' -not -path '*/.git/*')
[ $fail -eq 0 ] && echo "  ok   $(find "$DST" -name '*.sh' -not -path '*/.git/*' | wc -l) scripts parse"

echo
echo "=== environment health, final ==="
export HSA_ENABLE_DXG_DETECTION=1
printf '  torch          : %s\n' "$("$HOME/genai_env/bin/python3" -c 'import torch;print(torch.__version__)' 2>/dev/null)"
printf '  GPU visible    : %s\n' "$("$HOME/genai_env/bin/python3" -c 'import torch;print(torch.cuda.is_available())' 2>/dev/null)"
printf '  ComfyUI models : %s\n' "$(find "$HOME/ComfyUI/models" -type f \( -name '*.safetensors' -o -name '*.ckpt' -o -name '*.gguf' \) 2>/dev/null | wc -l)"
printf '  ComfyUI images : %s\n' "$(find "$HOME/ComfyUI/output" -type f 2>/dev/null | wc -l)"
