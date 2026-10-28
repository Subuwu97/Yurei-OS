#!/usr/bin/env python3
"""Turns the approved design files in branding/source/ into theme assets.

    python3 branding/build-assets.py

Needs ffmpeg, Pillow, numpy and opencv-python-headless. Outputs (committed,
so packaging needs none of these tools):

  themes/plymouth/yurei/frame-NNN.png  unique boot animation frames
  themes/plymouth/yurei/yurei.script   generated from yurei.script.in
  themes/sddm/yurei/assets/logo.png    transparent wordmark
  themes/sddm/yurei/assets/background.jpg  login artwork, baked-in UI removed
  overlay/boot/splash.png              boot menu background with the new wordmark
  pkg/yurei-settings/files/usr/share/wallpapers/Yurei/  desktop wallpaper

The source files are design assets: the video carries a "motion concept"
caption and the login reference has a mock-up UI painted into it. Both are
removed here rather than shipped.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "branding" / "source"
PLYMOUTH = ROOT / "themes" / "plymouth" / "yurei"
SDDM = ROOT / "themes" / "sddm" / "yurei"

BG = np.array([6, 12, 31])  # the flat navy behind the video and the logo

# Boot animation (1280x720, 24 fps, 192 frames)
CAPTION_ROWS = (660, 700)  # "BOOT ANIMATION · MOTION CONCEPT"
LOOP_START = 150  # from here on she waves next to the logo: loops while booting
STATIC_PIXELS = 200  # frames differing in fewer pixels than this count as identical
# Plymouth copies the theme into every initramfs (CachyOS installs two kernels,
# each with a fallback image), so frames are stored at 85% with 128 colours:
# ~6 MB instead of ~9, with no visible difference. The script scales to fit.
FRAME_SCALE = 0.85
FRAME_COLORS = 128

# The login design (1672x941). Its mock-up UI is painted in; these are the
# areas to repair, in its pixels. The theme puts its real controls in the
# same places (see LOGIN_LAYOUT in themes/sddm/yurei/Main.qml).
# Bright strokes (text, wordmark) are masked by brightness inside these boxes,
# so the scenery between the letters survives.
BAKED_TEXT = [
    (350, 168, 812, 372),   # wordmark with its flame
    (516, 538, 594, 570),   # "Alex"
    (498, 659, 614, 686),   # "Switch user"
    (1386, 860, 1422, 887),  # "US"
]
BAKED_SHAPES = [  # ("circle", cx, cy, r) or ("pill", x0, y0, x1, y1)
    ("circle", 555, 457, 69),          # avatar and its ring
    ("pill", 366, 576, 746, 648),      # password field
    ("circle", 67, 872, 30),           # gear
    ("pill", 94, 845, 270, 898),       # session menu
    ("circle", 1471, 873, 33),         # sleep
    ("circle", 1538, 873, 33),         # restart
    ("circle", 1605, 873, 33),         # power
]
AVATAR = (555, 457, 61)  # the design's avatar picture: the default avatar

def log(msg: str) -> None:
    print(f"  {msg}", file=sys.stderr)


# --- boot animation --------------------------------------------------------

def video_frames(path: Path) -> list[np.ndarray]:
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), f"{tmp}/f%03d.png"], check=True)
        return [np.asarray(Image.open(f).convert("RGB")).copy() for f in sorted(Path(tmp).glob("f*.png"))]


def transparent_background(img: Image.Image) -> Image.Image:
    """Makes the background palette entry transparent. Plymouth's scaling
    shifts colours by a level, which would show the frame's edges against
    the screen; with a transparent background the screen colour shows
    through instead."""
    palette = np.array(img.getpalette()[:FRAME_COLORS * 3]).reshape(-1, 3)
    nearest = int(np.abs(palette - BG).sum(axis=1).argmin())
    img.info["transparency"] = nearest
    return img


def build_plymouth() -> np.ndarray:
    """Builds the boot animation; returns the final (waving) frame at full size."""
    frames = video_frames(SRC / "Yurei-Boot-Animation.mp4")
    for f in frames:
        f[CAPTION_ROWS[0]:CAPTION_ROWS[1], :] = BG
        # video compression leaves the background a level or two off; make it
        # exact so the frame edges vanish against Plymouth's background colour
        f[np.abs(f.astype(int) - BG).max(axis=2) <= 4] = BG

    # crop to everything that ever moves, plus a margin
    union = np.zeros(frames[0].shape[:2], bool)
    for f in frames:
        union |= np.abs(f.astype(int) - BG).max(axis=2) > 14
    ys, xs = np.nonzero(union)
    margin = 12
    y0, y1 = max(ys.min() - margin, 0), min(ys.max() + margin, union.shape[0])
    x0, x1 = max(xs.min() - margin, 0), min(xs.max() + margin, union.shape[1])
    frames = [f[y0:y1, x0:x1] for f in frames]

    # store each distinct image once; the timeline says which to show per tick
    unique: list[np.ndarray] = []
    timeline: list[int] = []
    for f in frames:
        if unique:
            changed = (np.abs(f.astype(int) - unique[-1].astype(int)).max(axis=2) > 12).sum()
            if changed < STATIC_PIXELS:
                timeline.append(len(unique) - 1)
                continue
        unique.append(f)
        timeline.append(len(unique) - 1)

    for old in PLYMOUTH.glob("frame-*.png"):
        old.unlink()
    PLYMOUTH.mkdir(parents=True, exist_ok=True)
    total = 0
    width, height = round((x1 - x0) * FRAME_SCALE), round((y1 - y0) * FRAME_SCALE)
    for i, f in enumerate(unique):
        img = Image.fromarray(f).resize((width, height), Image.Resampling.LANCZOS)
        img = img.quantize(colors=FRAME_COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        img = transparent_background(img)
        out = PLYMOUTH / f"frame-{i:03d}.png"
        img.save(out, optimize=True, transparency=img.info["transparency"])
        total += out.stat().st_size

    template = (PLYMOUTH / "yurei.script.in").read_text()
    script = (template
              .replace("@FRAME_WIDTH@", str(width))
              .replace("@FRAME_HEIGHT@", str(height))
              # Plymouth's script language has no array literals
              .replace("@TIMELINE@", "\n".join(f"timeline[{i}] = {f};" for i, f in enumerate(timeline)))
              .replace("@LOOP_START@", str(LOOP_START))
              .replace("@TICKS@", str(len(timeline))))
    (PLYMOUTH / "yurei.script").write_text(script)
    log(f"plymouth: {len(unique)} unique frames of {len(timeline)}, {width}x{height}, {total / 1e6:.1f} MB")
    return unique[-1]


# --- logo ------------------------------------------------------------------

def color_to_alpha(rgb: np.ndarray, bg: np.ndarray) -> np.ndarray:
    """Removes a background colour, keeping glows as soft transparency
    (the same idea as GIMP's colour-to-alpha)."""
    p = rgb.astype(float)
    b = bg.astype(float)
    headroom = np.where(p >= b, 255 - b, b)
    alpha = np.clip((np.abs(p - b) / np.maximum(headroom, 1)).max(axis=2), 0, 1)
    # compression noise in the background would otherwise become a faint
    # box of near-invisible pixels; ramp alpha up from a small floor instead
    alpha = np.clip((alpha - 0.05) / 0.95, 0, 1)
    a = alpha[..., None]
    color = np.where(a > 0, (p - b * (1 - a)) / np.maximum(a, 1e-6), 0)
    rgba = np.dstack([np.clip(color, 0, 255), alpha * 255]).astype(np.uint8)
    return rgba


def build_logo() -> Image.Image:
    rgb = np.asarray(Image.open(SRC / "Yurei-Logo.png").convert("RGB"))
    rgba = color_to_alpha(rgb, BG)
    logo = Image.fromarray(rgba, "RGBA")
    # drop near-invisible noise from compression before cropping
    a = np.asarray(logo)[..., 3]
    ys, xs = np.nonzero(a > 40)
    pad = 20
    logo = logo.crop((max(xs.min() - pad, 0), max(ys.min() - pad, 0),
                      min(xs.max() + pad, logo.width), min(ys.max() + pad, logo.height)))
    logo.thumbnail((1200, 1200), Image.Resampling.LANCZOS)
    out = SDDM / "assets" / "logo.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    logo.save(out, optimize=True)
    log(f"logo: {logo.size}")
    return logo


# --- login background --------------------------------------------------------

def build_login_background() -> None:
    ref = cv2.imread(str(SRC / "Yurei-Login-Reference.png"))

    # the moon-over-torii picture in the design's avatar becomes the default
    # picture for accounts without their own
    cx, cy, r = AVATAR
    avatar = Image.fromarray(cv2.cvtColor(ref[cy - r:cy + r, cx - r:cx + r], cv2.COLOR_BGR2RGB))
    avatar.resize((256, 256), Image.Resampling.LANCZOS).save(SDDM / "assets" / "avatar.png", optimize=True)

    mask = np.zeros(ref.shape[:2], np.uint8)
    gray = cv2.cvtColor(ref, cv2.COLOR_BGR2GRAY)
    hsv = cv2.cvtColor(ref, cv2.COLOR_BGR2HSV)
    for x0, y0, x1, y1 in BAKED_TEXT:
        # white/lavender strokes and their glow: bright and only lightly saturated
        region = (gray[y0:y1, x0:x1] > 120) & (hsv[y0:y1, x0:x1, 1] < 140)
        mask[y0:y1, x0:x1][region] = 255
    mask = cv2.dilate(mask, np.ones((7, 7), np.uint8))
    for shape in BAKED_SHAPES:
        if shape[0] == "circle":
            _, cx, cy, r = shape
            cv2.circle(mask, (cx, cy), r, 255, -1)
        else:
            _, x0, y0, x1, y1 = shape
            r = (y1 - y0) // 2
            cv2.rectangle(mask, (x0 + r, y0), (x1 - r, y1), 255, -1)
            cv2.circle(mask, (x0 + r, y0 + r), r, 255, -1)
            cv2.circle(mask, (x1 - r, y0 + r), r, 255, -1)
    clean = cv2.inpaint(ref, mask, 7, cv2.INPAINT_TELEA)
    # soften the repaired areas slightly so they read as haze, not smears
    soft = cv2.GaussianBlur(clean, (0, 0), 4)
    feather = cv2.GaussianBlur(mask, (0, 0), 6).astype(float)[..., None] / 255
    clean = (clean * (1 - feather) + soft * feather).astype(np.uint8)

    img = Image.fromarray(cv2.cvtColor(clean, cv2.COLOR_BGR2RGB))
    # the design is 941 px tall: upscale for 1440p+ screens, sharpen lightly
    img = img.resize((img.width * 2, img.height * 2), Image.Resampling.LANCZOS)
    img = img.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    out = SDDM / "assets" / "background.jpg"
    img.save(out, quality=90, optimize=True, progressive=True)
    log(f"login background: {img.size}, {out.stat().st_size / 1e6:.1f} MB")


# --- boot menu splash ------------------------------------------------------

def build_boot_splash(logo: Image.Image, wave: np.ndarray) -> None:
    """The GRUB/syslinux background: the mascot's final waving pose from the
    animation in the lower right, the wordmark top-left, and the centre left
    clear for the menu. The pose sits on the same flat navy as the canvas,
    so it needs no cut-out."""
    canvas = Image.new("RGB", (1920, 1080), tuple(int(c) for c in BG))
    frame = Image.fromarray(wave)
    # the right half of the final frame is the mascot and her spirit
    mascot = frame.crop((frame.width // 2, 0, frame.width, frame.height))
    scale = 860 / mascot.height
    mascot = mascot.resize((round(mascot.width * scale), 860), Image.Resampling.LANCZOS)
    canvas.paste(mascot, (1920 - mascot.width - 40, 1080 - mascot.height - 30))
    mark = logo.copy()
    mark.thumbnail((460, 230), Image.Resampling.LANCZOS)
    canvas.paste(mark, (56, 40), mark)
    canvas.save(ROOT / "overlay" / "boot" / "splash.png", optimize=True)
    log("boot menu splash: 1920x1080")


def build_plymouth_widgets() -> None:
    """Password box, bullet and lock drawn as images, so a disk-unlock prompt
    stays visible even when the initramfs has no font support."""
    from PIL import ImageDraw
    s = 4  # draw large, then downsample for smooth edges
    box = Image.new("RGBA", (420 * s, 56 * s))
    d = ImageDraw.Draw(box)
    d.rounded_rectangle((0, 0, box.width - 1, box.height - 1), radius=28 * s,
                        fill=(14, 20, 48, 225), outline=(185, 170, 255, 200), width=2 * s)
    box.resize((420, 56), Image.Resampling.LANCZOS).save(PLYMOUTH / "entry.png")

    dot = Image.new("RGBA", (14 * s, 14 * s))
    ImageDraw.Draw(dot).ellipse((0, 0, dot.width - 1, dot.height - 1), fill=(236, 232, 255, 255))
    dot.resize((14, 14), Image.Resampling.LANCZOS).save(PLYMOUTH / "bullet.png")

    lock = Image.new("RGBA", (22 * s, 26 * s))
    d = ImageDraw.Draw(lock)
    d.rounded_rectangle((0, 10 * s, 22 * s - 1, 26 * s - 1), radius=4 * s, fill=(185, 170, 255, 255))
    d.arc((4 * s, 0, 18 * s, 22 * s), 180, 360, fill=(185, 170, 255, 255), width=3 * s)
    lock.resize((22, 26), Image.Resampling.LANCZOS).save(PLYMOUTH / "lock.png")


def build_wallpaper() -> None:
    """The desktop wallpaper as a Plasma wallpaper package: the design at its
    own size and 2x for 1440p/4K screens; Plasma picks the closer one."""
    images = ROOT / "pkg/yurei-settings/files/usr/share/wallpapers/Yurei/contents/images"
    for old in images.glob("*"):
        old.unlink()
    images.mkdir(parents=True, exist_ok=True)
    art = Image.open(SRC / "Yurei-Wallpaper.png").convert("RGB")
    art.save(images / f"{art.width}x{art.height}.jpg", quality=92, optimize=True, progressive=True)
    big = art.resize((art.width * 2, art.height * 2), Image.Resampling.LANCZOS)
    big = big.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    big.save(images / f"{big.width}x{big.height}.jpg", quality=90, optimize=True, progressive=True)
    log(f"wallpaper: {art.width}x{art.height} and {big.width}x{big.height}")


def main() -> None:
    wave = build_plymouth()
    build_plymouth_widgets()
    logo = build_logo()
    build_login_background()
    build_boot_splash(logo, wave)
    build_wallpaper()


if __name__ == "__main__":
    main()
