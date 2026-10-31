#!/usr/bin/env python3
"""Compare an extracted appearance package/system root with shared source assets.

Run with Python 3; no Qt, package manager or root privileges are required.
This checks asset parity, not defaults activation or rendered appearance.
"""

import argparse
import hashlib
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
FILES = REPO / "pkg/yurei-settings/files"
MAPPINGS = (
    (REPO / "themes/plasma/yurei", "usr/share/plasma/look-and-feel/org.yurei.desktop"),
    (REPO / "themes/sddm/yurei", "usr/share/sddm/themes/yurei"),
    (FILES / "usr/share/color-schemes", "usr/share/color-schemes"),
    (FILES / "usr/share/wallpapers", "usr/share/wallpapers"),
    (FILES / "usr/share/icons", "usr/share/icons"),
    (FILES / "usr/share/konsole", "usr/share/konsole"),
)


def expected_files():
    for source, destination in MAPPINGS:
        if not source.is_dir():
            raise ValueError(f"missing source directory: {source}")
        for file in sorted(source.rglob("*")):
            if file.is_file():
                yield file, Path(destination) / file.relative_to(source)
    plymouth = REPO / "themes/plymouth/yurei"
    for file in sorted(plymouth.iterdir()):
        if file.suffix == ".png" or file.name in ("yurei.script", "yurei.plymouth"):
            yield file, Path("usr/share/plymouth/themes/yurei") / file.name


def check(root):
    errors = []
    count = 0
    for source, relative in expected_files():
        count += 1
        target = root / relative
        if not target.is_file():
            errors.append(f"missing: {relative.as_posix()}")
        elif hashlib.sha256(source.read_bytes()).digest() != hashlib.sha256(target.read_bytes()).digest():
            errors.append(f"different: {relative.as_posix()}")
    # Match the existing package's generated global-theme layout exactly.
    layout = Path("usr/share/plasma/look-and-feel/org.yurei.desktop/contents/layouts/org.kde.plasma.desktop-layout.js")
    script = FILES / "usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/yurei-desktop-layout.js"
    expected = b'var yureiLayout = "dock";\n' + script.read_bytes()
    count += 1
    if not (root / layout).is_file():
        errors.append(f"missing: {layout.as_posix()}")
    elif (root / layout).read_bytes() != expected:
        errors.append(f"different: {layout.as_posix()}")
    return count, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="extracted package or mounted system root (read only)")
    args = parser.parse_args()
    if not args.root.is_dir():
        parser.error("root must be an existing directory")
    count, errors = check(args.root)
    for error in errors:
        print(error)
    print(f"{count} assets checked; {len(errors)} mismatches")
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
