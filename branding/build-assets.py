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
                                       (also the installed system's Limine menu)
  pkg/yurei-settings/files/usr/share/wallpapers/Yurei/  desktop wallpaper
  themes/ksplash/yurei/                Plasma's splash after login (the wave, continued)
  overlay/airootfs/usr/share/calamares/branding/yurei/  installer images

Run single steps with their names, e.g. `build-assets.py ksplash calamares`;
the later steps reuse the earlier ones' committed outputs. The installer's
icon is rendered from branding/icon.svg with PySide6 (Qt SVG).

The source files are design assets: the video carries a "motion concept"
caption and the login reference has a mock-up UI painted into it. Both are
removed here rather than shipped.
"""

from __future__ import annotations

import re
import shutil
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
KSPLASH = ROOT / "themes" / "ksplash" / "yurei"
CALAMARES = ROOT / "overlay" / "airootfs" / "usr" / "share" / "calamares" / "branding" / "yurei"
WALLPAPER = ROOT / "pkg/yurei-settings/files/usr/share/wallpapers/Yurei/contents/images"

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
    # the installed system's Limine menu uses it too (see yurei-install-target)
    canvas.save(ROOT / "pkg/yurei-settings/files/usr/share/yurei/boot-splash.png", optimize=True)
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
    images = WALLPAPER
    for old in images.glob("*"):
        old.unlink()
    images.mkdir(parents=True, exist_ok=True)
    art = Image.open(SRC / "Yurei-Wallpaper.png").convert("RGB")
    art.save(images / f"{art.width}x{art.height}.jpg", quality=92, optimize=True, progressive=True)
    big = art.resize((art.width * 2, art.height * 2), Image.Resampling.LANCZOS)
    big = big.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    big.save(images / f"{big.width}x{big.height}.jpg", quality=90, optimize=True, progressive=True)
    log(f"wallpaper: {art.width}x{art.height} and {big.width}x{big.height}")


# --- Plasma splash ------------------------------------------------------------

def plymouth_loop() -> tuple[list[int], int, int]:
    """The waving loop as the boot animation plays it: (frames, width, height)."""
    script = (PLYMOUTH / "yurei.script").read_text()
    values = dict(re.findall(r"^(frame_width|frame_height|loop_start|ticks) = (\d+);", script, re.M))
    timeline = {int(t): int(f) for t, f in re.findall(r"^timeline\[(\d+)\] = (\d+);", script, re.M)}
    start, ticks = int(values["loop_start"]), int(values["ticks"])
    return [timeline[t] for t in range(start, ticks)], int(values["frame_width"]), int(values["frame_height"])


def build_ksplash() -> None:
    """Plasma's splash after login carries on from the boot animation: the
    same waving loop, at the same size and place on the same navy, so
    Plymouth hands over to the desktop without a jump."""
    loop, width, height = plymouth_loop()
    images = KSPLASH / "contents" / "splash" / "images"
    for old in images.glob("wave-*.png"):
        old.unlink()
    images.mkdir(parents=True, exist_ok=True)
    frames = sorted(set(loop))
    for i, f in enumerate(frames):
        shutil.copyfile(PLYMOUTH / f"frame-{f:03d}.png", images / f"wave-{i:02d}.png")
    (KSPLASH / "contents" / "splash" / "wave.js").write_text(
        "// GENERATED by branding/build-assets.py from the boot animation's loop\n"
        ".pragma library\n"
        f"var frameWidth = {width};\n"
        f"var frameHeight = {height};\n"
        f"var frameCount = {len(frames)};\n"
        f"var timeline = [{', '.join(str(frames.index(f)) for f in loop)}];\n")
    # preview for System Settings > Colours & Themes > Splash Screen
    preview = Image.new("RGB", (1920, 1080), tuple(int(c) for c in BG))
    wave = Image.open(PLYMOUTH / f"frame-{loop[0]:03d}.png").convert("RGBA")
    scale = min(1920 * 0.92 / width, 1080 * 0.62 / height)
    wave = wave.resize((round(width * scale), round(height * scale)), Image.Resampling.LANCZOS)
    preview.paste(wave, ((1920 - wave.width) // 2, round((1080 - wave.height) * 0.4)), wave)
    preview.thumbnail((960, 540), Image.Resampling.LANCZOS)
    (KSPLASH / "contents" / "previews").mkdir(parents=True, exist_ok=True)
    preview.save(KSPLASH / "contents" / "previews" / "splash.png", optimize=True)
    log(f"plasma splash: {len(frames)} frames, loop of {len(loop)}")


# --- installer (Calamares) -------------------------------------------------------

def render_icon(size: int) -> Image.Image:
    from PySide6.QtCore import Qt
    from PySide6.QtGui import QGuiApplication, QImage, QPainter
    from PySide6.QtSvg import QSvgRenderer
    _app = QGuiApplication.instance() or QGuiApplication(["build-assets", "-platform", "offscreen"])
    img = QImage(size, size, QImage.Format.Format_RGBA8888)
    img.fill(Qt.GlobalColor.transparent)
    painter = QPainter(img)
    QSvgRenderer(str(ROOT / "branding" / "icon.svg")).render(painter)
    painter.end()
    return Image.frombytes("RGBA", (size, size), bytes(img.constBits()))


def build_calamares() -> None:
    """Images for the installer's Yūrei branding: the icon, the wordmark on
    its welcome page, and backgrounds for the slides shown while it installs
    (their text lives in show.qml, so it stays sharp and editable)."""
    CALAMARES.mkdir(parents=True, exist_ok=True)
    render_icon(128).save(CALAMARES / "icon.png", optimize=True)
    render_icon(96).save(CALAMARES / "logo.png", optimize=True)
    logo = Image.open(SDDM / "assets" / "logo.png")
    logo.thumbnail((560, 224), Image.Resampling.LANCZOS)
    logo.save(CALAMARES / "welcome.png", optimize=True)

    def slide(img: Image.Image, name: str, focus: float, zoom: float = 1) -> None:
        # 2.3:1 like the installer's slide area; `focus` is where to crop
        # (0 left, 1 right), `zoom` how much of the width to keep (1/zoom)
        img = img.convert("RGB")
        w = round(img.width / zoom)
        h = round(w / 2.3)
        if h > img.height:
            h, w = img.height, round(img.height * 2.3)
        x = round((img.width - w) * focus)
        y = round((img.height - h) * 0.45)
        img = img.crop((x, y, x + w, y + h)).resize((1380, 600), Image.Resampling.LANCZOS)
        img.save(CALAMARES / name, quality=88, optimize=True, progressive=True)

    slide(Image.open(sorted(WALLPAPER.glob("*.jpg"))[0]), "slide-shrine.jpg", 0.5)
    # the right of the login art: its left holds the repaired wordmark area
    slide(Image.open(SDDM / "assets" / "background.jpg"), "slide-moon.jpg", 1.0, 1.6)
    # the waving mascot from the boot menu art, on its navy, at the right
    splash = Image.open(ROOT / "overlay" / "boot" / "splash.png").convert("RGB")
    mascot = splash.crop((1000, 150, 1920, 1080))
    mascot = mascot.resize((round(mascot.width * 570 / mascot.height), 570), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (1380, 600), tuple(int(c) for c in BG))
    canvas.paste(mascot, (1380 - mascot.width - 40, 15))
    canvas.save(CALAMARES / "slide-wave.jpg", quality=88, optimize=True, progressive=True)
    log("installer branding: icon, logo, welcome, 3 slide backgrounds")


STEPS = ["plymouth", "logo", "login", "boot-splash", "wallpaper", "ksplash", "calamares"]


def main() -> None:
    steps = sys.argv[1:] or STEPS
    unknown = set(steps) - set(STEPS)
    if unknown:
        sys.exit(f"unknown step(s): {', '.join(sorted(unknown))}; choose from {', '.join(STEPS)}")
    wave = logo = None
    if "plymouth" in steps:
        wave = build_plymouth()
        build_plymouth_widgets()
    if "logo" in steps:
        logo = build_logo()
    if "login" in steps:
        build_login_background()
    if "boot-splash" in steps:
        if wave is None:  # it uses the video's last frame at full size
            sys.exit("boot-splash needs the plymouth step too")
        build_boot_splash(logo or Image.open(SDDM / "assets" / "logo.png"), wave)
    if "wallpaper" in steps:
        build_wallpaper()
    if "ksplash" in steps:
        build_ksplash()
    if "calamares" in steps:
        build_calamares()


if __name__ == "__main__":
    main()
