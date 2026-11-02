#!/usr/bin/env python3
"""Stage only visual assets; keep the shared source themes byte-identical."""
import argparse
import shutil
from pathlib import Path


def stage(repository, destination):
    destination = Path(destination)
    if destination.exists() and any(destination.iterdir()):
        raise SystemExit("Appearance staging requires an empty destination")
    destination.mkdir(parents=True, exist_ok=True)
    files = repository / "pkg/yurei-settings/files"
    pairs = [
        (repository / "themes/plasma/yurei", "usr/share/plasma/look-and-feel/org.yurei.desktop"),
        (repository / "themes/sddm/yurei", "usr/share/sddm/themes/yurei"),
        (repository / "themes/plymouth/yurei", "usr/share/plymouth/themes/yurei"),
    ]
    for relative in ["usr/share/color-schemes/Yurei.colors", "usr/share/konsole/Yurei.profile", "usr/share/konsole/Yurei.colorscheme", "usr/share/wallpapers/Yurei", "usr/share/icons/hicolor/scalable/apps/yurei.svg", "usr/share/pixmaps/yurei.svg", "etc/xdg/kdeglobals", "etc/xdg/ksplashrc", "etc/xdg/kscreenlockerrc", "etc/xdg/konsolerc"]:
        pairs.append((files / relative, relative))
    pairs.extend([
        (files / "usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/yurei-desktop-layout.js", "usr/share/yurei/desktop-layout.js"),
        (repository / "ARTWORK.md", "usr/share/licenses/yurei-appearance/ARTWORK.md"),
    ])
    for source, relative in pairs:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            shutil.copy2(source, target)
    print("Staged Yurei visual assets without distribution-specific tools")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    stage(Path(__file__).resolve().parents[2], args.destination)
