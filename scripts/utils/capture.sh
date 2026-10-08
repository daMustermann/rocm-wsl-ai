#!/bin/bash
# Capture README screenshots from the real UI.
#
# The demo is run inside a pty on purpose: lib/common.sh only emits colour when
# stdout is a terminal (`[ -t 1 ]`), so piping it straight to a file produces an
# image with every escape sequence stripped. Running under `script` gives it a
# terminal, which is also exactly what a user sees.
#
# Usage: bash capture.sh [output-dir]   (run from the repository root)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$ROOT/docs/assets}"
RAW="$(mktemp)"
trap 'rm -f "$RAW"' EXIT

cd "$ROOT" || exit 1

echo "capture: rendering the UI in a pty ..."
# TERM drives the colour-capability check in lib/common.sh; xterm-256color is
# what a real WSL terminal reports and is what the palette is written for.
# The timeout is a guard: --demo is supposed to never block, so if it does, the
# capture should still produce whatever was rendered rather than hanging.
COLUMNS=100 timeout -s KILL 180 \
    script -qec "env TERM=xterm-256color CLICOLOR_FORCE=1 ./menu.sh --demo" /dev/null > "$RAW" 2>&1 || true

if [ ! -s "$RAW" ]; then
    echo "capture: no output produced — is gum installed?" >&2
    exit 1
fi

echo "capture: $(wc -l < "$RAW") lines captured"

python3 "$ROOT/scripts/utils/capture.py" --input "$RAW" --out "$OUT" || exit 1

# PNG as well as SVG: GitHub renders SVG in markdown, but image previews,
# terminals and every other viewer do not reliably.
if command -v rsvg-convert >/dev/null 2>&1; then
    echo "capture: converting to PNG ..."
    ( cd "$OUT" && shopt -s nullglob
      for f in ui-*.svg; do
          base="${f%.svg}"
          rsvg-convert -z 2 -o "$base.png" "$f" && echo "capture: $base.png"
      done )
else
    echo "capture: rsvg-convert not found — SVG only (apt install librsvg2-bin)"
fi