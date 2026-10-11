#!/bin/bash
# Toggle extra ComfyUI args in user.env, idempotently. Used per big-model job.
#
#   ./comfy_args.sh lowvram      add --lowvram
#   ./comfy_args.sh reserve      add --reserve-vram 1.5
#   ./comfy_args.sh off          remove both
#   ./comfy_args.sh show         show current
ENV_FILE="$HOME/.config/rocm-wsl-ai/user.env"
KEY=COMFYUI_EXTRA_ARGS

set_v() {
    local val="$1"
    mkdir -p "$(dirname "$ENV_FILE")"
    touch "$ENV_FILE"
    if [ -z "$val" ]; then
        grep -v "^export ${KEY}=" "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null || true
        mv "$ENV_FILE.tmp" "$ENV_FILE"
    else
        grep -v "^export ${KEY}=" "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null || true
        printf 'export %s="%s"\n' "$KEY" "$val" >> "$ENV_FILE.tmp"
        mv "$ENV_FILE.tmp" "$ENV_FILE"
    fi
    echo "$KEY=\"${val:-<unset>}\""
}

show() {
    if grep -q "^export ${KEY}=" "$ENV_FILE" 2>/dev/null; then
        grep "^export ${KEY}=" "$ENV_FILE"
    else
        echo "${KEY}=<unset>"
    fi
}

case "${1:-show}" in
    lowvram) set_v "--lowvram" ;;
    reserve) set_v "--reserve-vram 1.5" ;;
    off)     set_v "" ;;
    show)    show ;;
    *)       echo "usage: $0 {lowvram|reserve|off|show}"; exit 2 ;;
esac