#!/bin/bash
set -uo pipefail
SRC=/mnt/f/Coding/rocm-wsl-ai-2
DST="$HOME/rocm-wsl-ai"
export PATH="$HOME/.local/bin:$PATH"

cd "$SRC" || exit 1
rm -f .tunerstate.sh .gumhang.sh .kill.sh .testchoose.sh .patchchoose.py \
      .tunerverify.sh .sourcecheck.sh .sourcecheck2.sh .fixguard.py .tunerpty.py
rm -rf scripts/utils/__pycache__
git add -A
echo "=== staged ==="
git status --short | sed 's/^/  /'

git commit -q -F - <<'MSG'
Stop menus hanging: render selection ourselves instead of with gum

Running the auto-tuner hung indefinitely with a frozen screen and no output. The
cause was not the GPU: `gum choose`'s TUI only works when stdout is a terminal,
and the selection was captured with $(...), which makes stdout a pipe. gum then
cannot render, never reads keystrokes, and waits forever. Observed on a real
installation: the process sat for 10 minutes at 0.6% CPU, no benchmark ever
started, and Windows showed 6-10% GPU load from the idle desktop.

Fixes:

  * choose() no longer uses gum at all. It draws the menu with ANSI cursor
    control on stderr and prints only the result to stdout, so capturing the
    result cannot break the display. Arrow keys, j/k, digits and q are all
    handled; Esc cancels.
  * It requires a terminal on stdin, stdout AND stderr before using the cursor
    menu. Checking stdin alone was wrong: with output piped the drawing goes
    nowhere and the menu still looks frozen.
  * Without those terminals it falls back to a numbered prompt, which is more
    robust than a full-screen menu over a slow link anyway.
  * confirm() reads a single key directly for the same reason.
  * The three remaining `gum choose` sites — in smart_update.sh and
    update_ai_setup.sh — had the same latent hang and now use choose().
  * auto_tuner.sh never sourced lib/common.sh, so choose() was undefined; it
    relied on gum being present. It now sources both libraries explicitly.
  * Benchmark progress is unbuffered (PYTHONUNBUFFERED plus python -u). Python
    block-buffers stdout when it is not a terminal, so a multi-minute run could
    show nothing until it finished.
  * smart_update.sh's multi-select is now comma/space-separated numbers rather
    than a gum multi-select, and its dead plain-text fallback (unreachable after
    the rewrite) was removed.

Verified by running the tuner in a real pty: preflight passes, the menu renders,
the benchmark starts, and per-candidate progress lines appear as they happen.
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
echo "=== deploy to the active checkout ==="
cd "$DST" || exit 1
git fetch origin --quiet 2>/dev/null
# The deployed copy only ever tracks the remote; a hard reset avoids issues from
# locally amended commits and file-mode differences.
git reset --hard origin/main 2>&1 | tail -2 | sed 's/^/  /'
echo "  HEAD    : $(git rev-parse --short HEAD)"
echo "  VERSION : $(cat VERSION | tr -d ' \r\n')"
echo "  clean   : $([ -z "$(git status --porcelain)" ] && echo yes || echo no)"
echo "  choose uses gum? $(grep -c 'gum choose' lib/common.sh) reference(s) in common.sh (expect 0)"

echo
echo "=== final check: preflight and a real benchmark start ==="
export TOOLKIT_ROOT="$DST"
(
    cd "$DST" || exit 1
    source lib/common.sh; source lib/version.sh; source lib/migrate.sh; source lib/launch.sh
    ai_load_env >/dev/null 2>&1
    ai_preflight force
    echo "  preflight exit=$?"
)
