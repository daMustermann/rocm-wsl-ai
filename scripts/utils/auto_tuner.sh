#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    source "$SCRIPT_DIR/lib/common.sh"
else
    echo "common.sh missing"
    exit 1
fi

clear
echo ""
headline "✨ Magic Settings Auto-Tuner"
echo -e "$(gum style --foreground 117 "This will test different ROCm memory and attention profiles to find")\n$(gum style --foreground 117 "the fastest PyTorch combination for your specific GPU.")\n"

if ! is_wsl; then
    err "The Auto-Tuner is currently designed for WSL2."
    read -rp "Press Enter to return..."
    exit 1
fi

VENV_PATH="$HOME/genai_env"
if [ ! -f "$VENV_PATH/bin/activate" ]; then
    msgbox "Environment Not Found" "Virtual environment not found. Please install the Base Environment first."
    exit 1
fi

# We don't want to crash if HSA_OVERRIDE_GFX_VERSION is missing during bash strict mode
source "$VENV_PATH/bin/activate"
export HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-11.0.0}" 

log "Benchmarking started. Please wait, this takes about 15-20 seconds..."

# Define Profiles
declare -A PROFILES
PROFILES["0_Default"]="export MIGRAPHX_MLIR_USE_SPECIFIC_OPS="
PROFILES["1_MIGraphX_Attention"]="export MIGRAPHX_MLIR_USE_SPECIFIC_OPS=attention"
PROFILES["2_VRAM_Caching"]="export PYTORCH_HIP_ALLOC_CONF=garbage_collection_threshold:0.8,max_split_size_mb:512; export MIGRAPHX_MLIR_USE_SPECIFIC_OPS="
PROFILES["3_Extreme_Tuning"]="export PYTORCH_HIP_ALLOC_CONF=garbage_collection_threshold:0.8,max_split_size_mb:512; export MIGRAPHX_MLIR_USE_SPECIFIC_OPS=attention"

ORDER=("0_Default" "1_MIGraphX_Attention" "2_VRAM_Caching" "3_Extreme_Tuning")
DISPLAY_NAMES=("Default Baseline" "MIGraphX Attention Opt" "High VRAM Caching" "Extreme (Attention + Caching)")

BEST_INDEX=-1
BEST_TIME=999999.0

echo ""
gum style --bold "Running PyTorch AMD Optimizations:"
echo "--------------------------------------------------------"

for i in "${!ORDER[@]}"; do
    profile_key="${ORDER[$i]}"
    display_name="${DISPLAY_NAMES[$i]}"
    env_vars="${PROFILES[$profile_key]}"
    
    # Evaluate environment variables and launch the benchmark
    OUTPUT=$(eval "$env_vars && python $SCRIPT_DIR/scripts/utils/benchmark.py" 2>&1 || echo "SCORE: 9999.0")
    
    SCORE=$(echo "$OUTPUT" | grep "SCORE:" | awk '{print $2}' || echo "9999.0")
    
    gum style --foreground 212 "Testing [${display_name}] ... Time: ${SCORE}s"
    
    # Floating point comparison using awk
    if awk -v score="$SCORE" -v best="$BEST_TIME" 'BEGIN {exit !(score < best)}'; then
        BEST_TIME=$SCORE
        BEST_INDEX=$i
    fi
done

echo ""
if [ $BEST_INDEX -ge 0 ] && [ $(awk -v score="$BEST_TIME" 'BEGIN {print (score < 9900 ? 1 : 0)}') -eq 1 ]; then
    WINNER_NAME="${DISPLAY_NAMES[$BEST_INDEX]}"
    WINNER_KEY="${ORDER[$BEST_INDEX]}"
    
    gum style --border rounded --padding "1 2" --border-foreground 46 "$(gum style --bold --foreground 46 "🏆 Winner: $WINNER_NAME")" "Benchmark Time: ${BEST_TIME}s"
    
    if yesno "Apply Optimizations?" "Permanently save this optimized profile as your new default?"; then
        BEST_VARS="${PROFILES[$WINNER_KEY]}"
        
        echo "# Auto-Generated PyTorch ROCm Profile" > "$HOME/.genai_opt_profile"
        echo "$BEST_VARS" | tr ';' '\n' | sed 's/^ *//' >> "$HOME/.genai_opt_profile"
        
        msgbox "Applied!" "Your backend is now permanently tuned for maximum performance on your hardware!\n\nLaunch scripts will now automatically load these settings."
    fi
else
    err "Benchmark completely failed on all profiles. Check your PyTorch installation."
    read -rp "Press Enter to return..."
fi
