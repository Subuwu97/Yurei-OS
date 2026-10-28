#!/usr/bin/env python3
"""Runs the real Plymouth daemon with the Yūrei theme in a virtual X display
and checks what it draws. Also saves screenshots for review.

    sudo python3 tests/plymouth_check.py [--out DIR]

Needs root (it installs the theme to /usr/share/plymouth/themes/yurei and
points /etc/plymouth/plymouthd.conf at it), plus plymouth with its X11
renderer, Xvfb, xdotool, ImageMagick and Pillow. Meant for CI and throwaway
machines - on your own system, preview the installed theme instead
(see docs/THEMES.md).
"""

from __future__ import annotations

import argparse
import os
import pty
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from PIL import Image, ImageChops

THEME = Path(__file__).resolve().parent.parent / "themes" / "plymouth" / "yurei"
BG = (6, 12, 31)
DISPLAY = ":77"
failures: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"{'ok  ' if ok else 'FAIL'} {name}{f' ({detail})' if detail and not ok else ''}")
    if not ok:
        failures.append(name)


def grab(path: Path) -> Image.Image:
    png = subprocess.run(["import", "-window", "root", "png:-"], env=env(), check=True,
                         capture_output=True).stdout
    path.write_bytes(png)
    return Image.open(path).convert("RGB")


def env() -> dict:
    return dict(os.environ, DISPLAY=DISPLAY)


def client(*args: str, timeout: float = 5) -> None:
    try:
        subprocess.run(["plymouth", *args], env=env(), timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        pass


class Daemon:
    def __init__(self, logdir: Path, mode: str | None = None):
        master, slave = pty.openpty()
        cmd = ["plymouthd", "--no-daemon", "--debug", f"--debug-file={logdir}/plymouthd-{mode or 'boot'}.log",
               f"--tty={os.ttyname(slave)}",
               "--kernel-command-line=quiet splash plymouth.ignore-udev plymouth.ignore-serial-consoles"]
        if mode:
            cmd.append(f"--mode={mode}")
        self.proc = subprocess.Popen(cmd, env=env(), stdin=slave, stdout=slave, stderr=slave)
        time.sleep(1)
        client("show-splash")
        # the X11 renderer takes a few seconds to open its window
        deadline = time.time() + 12
        while time.time() < deadline:
            time.sleep(0.5)
            png = subprocess.run(["import", "-window", "root", "-crop", "1x1+5+5", "txt:-"],
                                 env=env(), capture_output=True, text=True).stdout
            if "#060C1F" in png.upper():
                break
        time.sleep(1)

    def stop(self) -> None:
        # "plymouth quit" can hang after a prompt under the X11 renderer
        # (not on real hardware, where systemd stops plymouthd itself)
        client("quit", timeout=3)
        for stop in (self.proc.terminate, self.proc.kill):
            try:
                self.proc.wait(timeout=3)
                return
            except subprocess.TimeoutExpired:
                stop()


def uniform_row(img: Image.Image, y: int) -> bool:
    """The frames' edges must not show: a row through empty space should be
    one colour from edge to edge."""
    row = img.crop((0, y, img.width, y + 1))
    return all(abs(a - b) <= 1 for px in row.getdata() for a, b in zip(px, BG))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path(tempfile.mkdtemp(prefix="yurei-plymouth-")))
    args = parser.parse_args()
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    if os.geteuid() != 0:
        sys.exit("run as root (see the docstring)")

    target = Path("/usr/share/plymouth/themes/yurei")
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(THEME, target, ignore=shutil.ignore_patterns("*.in"))
    Path("/etc/plymouth").mkdir(exist_ok=True)
    Path("/etc/plymouth/plymouthd.conf").write_text("[Daemon]\nTheme=yurei\n")

    def start_display():
        proc = subprocess.Popen(["Xvfb", DISPLAY, "-screen", "0", "1920x1080x24"],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1)
        return proc

    xvfb = start_display()
    try:
        # --- boot: animation, background, messages, password -----------------
        d = Daemon(out)
        first = grab(out / "boot-1.png")
        time.sleep(1.2)
        second = grab(out / "boot-2.png")
        check("background is the theme colour", first.getpixel((5, 5)) == BG, str(first.getpixel((5, 5))))
        check("animation moves", ImageChops.difference(first, second).getbbox() is not None)
        check("no visible frame edge", uniform_row(second, 120) and uniform_row(second, 1000))

        client("display-message", "--text=Checking disks")
        time.sleep(0.5)
        msg = grab(out / "message.png")
        check("status message shown", msg.crop((660, 1020, 1260, 1064)).getextrema()[0][1] > 100)

        answer_file = out / "answer.txt"
        with answer_file.open("w") as fh:
            asker = subprocess.Popen(["plymouth", "ask-for-password", "--prompt=Unlock cryptroot"],
                                     env=env(), stdout=fh, stderr=subprocess.STDOUT)
            time.sleep(1)
            windows = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", "."], env=env(),
                                     capture_output=True, text=True).stdout.split()
            if windows:
                subprocess.run(["xdotool", "windowfocus", windows[-1]], env=env(), check=False)
            subprocess.run(["xdotool", "type", "--delay", "60", "moonlit"], env=env(), check=False)
            time.sleep(0.6)
            prompt = grab(out / "password.png")
            subprocess.run(["xdotool", "key", "Return"], env=env(), check=False)
            try:
                asker.wait(timeout=5)
            except subprocess.TimeoutExpired:
                asker.kill()
        check("password reaches the caller", answer_file.read_text().strip() == "moonlit",
              answer_file.read_text().strip())
        # the entry box outline is light lavender on the dark background
        box = prompt.crop((700, 850, 1220, 1000))
        check("password box drawn", box.getextrema()[2][1] > 180)
        d.stop()
        # plymouthd writes its debug log only when it exits cleanly
        log_file = out / "plymouthd-boot.log"
        if log_file.exists():
            log = log_file.read_text(errors="replace")
            check("script plugin ran the theme", "executing script file" in log)
            check("X11 renderer used", "renderers/x11.so" in log)

        # --- shutdown: skips straight to the waving loop -----------------------
        # a fresh display: the X11 renderer can't reopen one after a forced stop
        xvfb.terminate()
        xvfb.wait()
        xvfb = start_display()
        d = Daemon(out, mode="shutdown")
        shut = grab(out / "shutdown.png")
        left = shut.crop((300, 300, 900, 700))  # where the wordmark sits in the loop
        check("shutdown shows the final pose with the logo", left.getextrema()[0][1] > 150)
        d.stop()
    finally:
        xvfb.terminate()

    print(f"screenshots in {out}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
