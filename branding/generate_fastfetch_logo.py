"""Regenerate the text-only Fastfetch mascot from the shared splash artwork.
Requires Pillow for maintainers; the distro package installs the generated text.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "themes/plasma/yurei/contents/splash/images/wave-00.png"
TARGET = ROOT / "independent/packages/fastfetch/yurei-logo.txt"
COLS, ROWS = 44, 30
DOTS = ((0, 0, 0), (0, 1, 1), (0, 2, 2), (1, 0, 3),
        (1, 1, 4), (1, 2, 5), (0, 3, 6), (1, 3, 7))


def generate():
    # Shared artwork is not changed. Crop only for sampling text cells;
    # the bounds include the full mascot and floating ghost.
    image = Image.open(SOURCE).convert("RGB").crop((545, 75, 830, 485))
    image = image.resize((COLS * 2, ROWS * 4), Image.Resampling.LANCZOS)
    lines = []
    for row in range(ROWS):
        line, last = "", None
        for col in range(COLS):
            mask, colors = 0, []
            for x, y, bit in DOTS:
                rgb = image.getpixel((col * 2 + x, row * 4 + y))
                if sum(abs(a - b) for a, b in zip(rgb, (7, 12, 30))) > 60:
                    mask |= 1 << bit
                    colors.append(rgb)
            if not mask:
                line += " "
                continue
            r, g, b = (sum(c[i] for c in colors) / len(colors) for i in range(3))
            color = 2 if b > r * 1.25 else 3 if r > b * 1.1 else 4 if min(r, g, b) > 165 else 1
            if color != last:
                line += "$" + str(color)
                last = color
            line += chr(0x2800 + mask)
        lines.append(line.rstrip())
    lines += ["", "$1                Y U R E I", "$2             Linux, with spirit"]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(generate(), encoding="utf-8", newline="\n")
