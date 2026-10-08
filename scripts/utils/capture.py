#!/usr/bin/env python3
"""Render terminal output to SVG, for the README.

Reads `menu.sh --demo` output and produces one SVG per screen. The point is that
the images come from the same code paths a user actually runs, so a screenshot
cannot drift from the UI the way a mock-up does.

Standard library only, Python 3.10+, and it never raises: a capture script that
crashes while generating documentation is worse than one that degrades.

Usage:
    ./menu.sh --demo | python3 scripts/utils/capture.py --out docs/assets
    python3 scripts/utils/capture.py --input raw.txt --out docs/assets
"""

from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path

ENGINE_VERSION = "1.0.0"

# ── Terminal palette ──────────────────────────────────────────────────────────
# xterm's 256 colours, so what the toolkit prints as 212 renders as the same
# pink here. The first 16 are the bright/normal ANSI names; 16-231 are the 6x6x6
# cube; 232-255 are the greyscale ramp.

_BASE16 = [
    "#1c1c1c", "#cc3333", "#4fb04f", "#c9a227", "#4f8fd6", "#a55cc9", "#3fa8a0", "#c8c8c8",
    "#6e6e6e", "#ff5f5f", "#5fff87", "#ffd75f", "#74b8ff", "#d68cff", "#5fe0d8", "#ffffff",
]


def _build_palette() -> list[str]:
    palette = list(_BASE16)
    levels = (0, 95, 135, 175, 215, 255)
    for r in levels:
        for g in levels:
            for b in levels:
                palette.append(f"#{r:02x}{g:02x}{b:02x}")
    for i in range(24):
        v = 8 + i * 10
        palette.append(f"#{v:02x}{v:02x}{v:02x}")
    return palette


PALETTE = _build_palette()

FG_DEFAULT = "#d6d6d6"
BG = "#12141a"
CHROME = "#1b1e26"

# DejaVu Sans Mono is named first deliberately. It has full box-drawing coverage
# (U+2500-U+257F) *and* a uniform advance, which is the only combination that
# keeps a bordered box on the character grid. Resolving `monospace` instead can
# pick a font without those glyphs, and the renderer then substitutes a fallback
# with a different advance — the border silently drifts right, run by run, while
# plain ASCII stays put.
FONT_STACK = "'DejaVu Sans Mono', 'Liberation Mono', 'Menlo', 'Consolas', monospace"

FONT_SIZE = 13.0
# DejaVu Sans Mono advance width is 1233/2048 em, so one cell at 13px is 7.83px.
# Deriving this from the font rather than guessing is what keeps the grid exact.
CHAR_W = 8.4
LINE_H = 19.0
PAD = 26
TITLEBAR = 30

# ── ANSI parsing ──────────────────────────────────────────────────────────────

# Anything that is not a colour change: cursor moves, erases, the alternate
# screen buffer, private modes, and the capability queries gum emits
# (ESC ]11;? and ESC [6n). Left in place they would show up as literal text or
# as stray box-drawing artefacts in the image.
_CSI_OTHER = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[=>]|\x1b\[[0-9;]*[JK]")
_SGR = re.compile(r"\x1b\[([0-9;]*)m")
_ANY_CSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[=>]")

_SCREEN_MARKER = re.compile(r"^\s*\x1b\[7m demo: (.+?) \x1b\[0m\s*$")


class Style:
    __slots__ = ("fg", "bg", "bold", "dim", "reverse")

    def __init__(self) -> None:
        self.fg: str | None = None
        self.bg: str | None = None
        self.bold = False
        self.dim = False
        self.reverse = False

    def copy(self) -> "Style":
        nxt = Style()
        nxt.fg, nxt.bg = self.fg, self.bg
        nxt.bold, nxt.dim, nxt.reverse = self.bold, self.dim, self.reverse
        return nxt


def _apply_sgr(style: Style, params: str) -> None:
    codes = [int(p) if p.isdigit() else 0 for p in params.split(";")] or [0]
    i = 0
    while i < len(codes):
        code = codes[i]
        if code == 0:
            style.fg = style.bg = None
            style.bold = style.dim = style.reverse = False
        elif code == 1:
            style.bold = True
        elif code == 2:
            style.dim = True
        elif code == 7:
            style.reverse = True
        elif code in (22, 21):
            style.bold = style.dim = False
        elif code == 27:
            style.reverse = False
        elif code == 39:
            style.fg = None
        elif code == 49:
            style.bg = None
        elif 30 <= code <= 37:
            style.fg = _BASE16[code - 30]
        elif 90 <= code <= 97:
            style.fg = _BASE16[code - 90 + 8]
        elif 40 <= code <= 47:
            style.bg = _BASE16[code - 40]
        elif code in (38, 48):
            target_is_fg = code == 38
            if i + 1 < len(codes) and codes[i + 1] == 5 and i + 2 < len(codes):
                idx = codes[i + 2]
                colour = PALETTE[idx] if 0 <= idx < len(PALETTE) else FG_DEFAULT
                if target_is_fg:
                    style.fg = colour
                else:
                    style.bg = colour
                i += 2
            elif i + 1 < len(codes) and codes[i + 1] == 2 and i + 4 < len(codes):
                r, g, b = codes[i + 2], codes[i + 3], codes[i + 4]
                colour = f"#{r & 255:02x}{g & 255:02x}{b & 255:02x}"
                if target_is_fg:
                    style.fg = colour
                else:
                    style.bg = colour
                i += 4
        i += 1


def _segments(line: str) -> list[tuple[str, Style]]:
    """Split a line into (text, style) runs."""
    style = Style()
    out: list[tuple[str, Style]] = []
    pos = 0
    for match in _SGR.finditer(line):
        if match.start() > pos:
            out.append((line[pos:match.start()], style.copy()))
        _apply_sgr(style, match.group(1))
        pos = match.end()
    if pos < len(line):
        out.append((line[pos:], style.copy()))
    return [(t, s) for t, s in out if t]


def _visible_width(text: str) -> int:
    """Width in cells. Combining marks count as zero, wide CJK as two."""
    width = 0
    for ch in text:
        if ch == "\t":
            width += 4
            continue
        import unicodedata

        if unicodedata.combining(ch):
            continue
        width += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return width


def _strip_nonsgr(text: str) -> str:
    return _ANY_CSI.sub("", text)


# ── SVG ───────────────────────────────────────────────────────────────────────

CHAR_W = 8.4
LINE_H = 19.0
PAD = 26
TITLEBAR = 30


def _escape(text: str) -> str:
    return html.escape(text, quote=True)


def _measure(body: str, fallback: int = 78) -> int:
    """Widest line in the body, in character cells.

    A fixed width either clips long lines (a GPU UUID in the diagnostics) or
    leaves a wide empty margin on short ones. Measuring per screen keeps every
    image tight without the caller having to know each screen's shape.
    """
    widest = 0
    for line in body.split("\n"):
        width = _visible_width(_strip_nonsgr(line))
        if width > widest:
            widest = width
    return max(widest, fallback if widest < fallback else 0, 40)


def render_svg(title: str, body: str, width_cells: int | None = None) -> str:
    lines = body.split("\n")
    while lines and not _strip_nonsgr(lines[-1]).strip():
        lines.pop()

    if width_cells is None:
        width_cells = _measure(body)
    width = int(PAD * 2 + width_cells * CHAR_W)
    height = int(TITLEBAR + PAD * 2 + max(len(lines), 1) * LINE_H)

    parts: list[str] = []
    parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" role="img" aria-label="{_escape(title)}">'
    )
    parts.append(f'<rect width="{width}" height="{height}" fill="{BG}" rx="10"/>')
    parts.append(
        f'<rect x="0" y="0" width="{width}" height="{TITLEBAR}" fill="{CHROME}" rx="10"/>'
        f'<rect x="0" y="{TITLEBAR - 10}" width="{width}" height="10" fill="{CHROME}"/>'
    )
    # Three window dots, then the screen name — reads as a terminal at a glance.
    for idx, colour in enumerate(("#ff5f57", "#febc2e", "#28c840")):
        parts.append(
            f'<circle cx="{18 + idx * 15}" cy="{TITLEBAR // 2}" r="5" fill="{colour}"/>'
        )
    parts.append(
        f'<text x="{width // 2}" y="{TITLEBAR // 2 + 4}" text-anchor="middle" '
        f'font-family="{FONT_STACK}" font-size="12" fill="#9aa0a8">{_escape(title)}</text>'
    )

    y = TITLEBAR + PAD
    for raw in lines:
        if raw.strip():
            x = PAD
            for text, st in _segments(raw):
                fg = st.fg or FG_DEFAULT
                bg = st.bg
                if st.reverse:
                    fg, bg = BG, st.fg or FG_DEFAULT
                opacity = "0.62" if st.dim else "1"
                weight = "bold" if st.bold else "normal"
                shown = _strip_nonsgr(text)
                # Width has to come from the *stripped* text. A run can start
                # with a terminal capability query that gum emits before any
                # colour change (`ESC ]11;? ESC \` for the background colour,
                # `ESC [6n` for the cursor position). Those bytes are not SGR, so
                # they stay inside this run — and counting them as visible cells
                # shifts everything in the run to the right by their length, which
                # is what pushed every bordered box out of alignment.
                cells = _visible_width(shown)
                width = cells * CHAR_W

                if bg and bg != BG:
                    parts.append(
                        f'<rect x="{x - 1}" y="{y - LINE_H + 4}" width="{width + 2}" '
                        f'height="{LINE_H - 2}" fill="{bg}"/>'
                    )

                attrs = (
                    f'font-family="{FONT_STACK}" font-size="{FONT_SIZE}" '
                    f'fill="{fg}" opacity="{opacity}" font-weight="{weight}" '
                    f'xml:space="preserve"'
                )

                if shown.isascii():
                    # Uniform-advance run: one element is enough.
                    parts.append(
                        f'<text x="{x:.2f}" y="{y}" {attrs}>{_escape(shown)}</text>'
                    )
                else:
                    # Every non-ASCII character gets its own element at an explicit
                    # x. Measured: the box header is a correct 55-cell rectangle in
                    # the captured data on all four lines, so any drift is the
                    # renderer laying out a run at the font's own advance rather
                    # than at one character cell — which is what a single <text>
                    # element allows. Arrows, ticks and box-drawing are exactly the
                    # glyphs that get substituted, so they are the ones pinned.
                    cx = x
                    for ch in shown:
                        parts.append(
                            f'<text x="{cx:.2f}" y="{y}" {attrs}>{_escape(ch)}</text>'
                        )
                        cx += _visible_width(ch) * CHAR_W
                x += width
        y += LINE_H

    parts.append("</svg>")
    return "\n".join(parts)


# ── Screens ───────────────────────────────────────────────────────────────────

def split_screens(text: str) -> list[tuple[str, str]]:
    screens: list[tuple[str, list[str]]] = []
    preamble: list[str] = []
    current: tuple[str, list[str]] | None = None

    for line in text.split("\n"):
        match = _SCREEN_MARKER.match(line)
        if match:
            current = (match.group(1).strip(), [])
            screens.append(current)
            continue
        if current is None:
            preamble.append(line)
        else:
            current[1].append(line)

    if preamble and any(l.strip() for l in preamble):
        screens.insert(0, ("startup", preamble))
    return [(name, "\n".join(lines)) for name, lines in screens]


def slug(name: str) -> str:
    keep = [c.lower() if c.isalnum() else "-" for c in name]
    out = "".join(keep)
    while "--" in out:
        out = out.replace("--", "-")
    return out.strip("-") or "screen"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", help="file to read instead of stdin")
    parser.add_argument("--out", default="docs/assets", help="output directory")
    parser.add_argument(
        "--width",
        type=int,
        default=0,
        help="minimum width in cells; 0 measures each screen (default)",
    )
    parser.add_argument("--prefix", default="ui-", help="output filename prefix")
    args = parser.parse_args(argv)

    if args.input:
        try:
            text = Path(args.input).read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            print(f"capture: cannot read {args.input}: {exc}", file=sys.stderr)
            return 1
    else:
        text = sys.stdin.read()

    # Screen-width resets from `clear` would otherwise blank earlier output, and
    # any line that is only an escape produces an empty row in the image.
    text = text.replace("\r\n", "\n").replace("\r", "")

    out_dir = Path(args.out)
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"capture: cannot create {out_dir}: {exc}", file=sys.stderr)
        return 1

    screens = split_screens(text)
    if not screens:
        print("capture: no screens found in the input", file=sys.stderr)
        return 1

    written = 0
    for name, body in screens:
        clean = "\n".join(l for l in body.split("\n") if not _CSI_OTHER.fullmatch(l.strip()))
        if not clean.strip():
            continue
        target = out_dir / f"{args.prefix}{slug(name)}.svg"
        measured = args.width if args.width > 0 else None
        try:
            target.write_text(render_svg(name, clean, measured), encoding="utf-8")
            written += 1
            print(f"capture: {target}")
        except OSError as exc:
            print(f"capture: cannot write {target}: {exc}", file=sys.stderr)

    print(f"capture: wrote {written} screen(s) to {out_dir}")
    return 0 if written else 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as exc:  # never let a doc helper take down a build
        print(f"capture: unexpected failure: {exc}", file=sys.stderr)
        sys.exit(1)