#!/usr/bin/env python3
"""Checks that every recipe in ORDER exists and that each recipe's version,
source address and SHA-256 are the ones in ../bootstrap/sources.lock, so the
packages are built from exactly the sources the bootstrap verified."""

import re
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
lock = {}
for line in (here.parent / "bootstrap" / "sources.lock").read_text().splitlines():
    fields = line.split()
    if fields and not line.startswith("#"):
        lock[fields[0]] = {"version": fields[1], "url": fields[2], "sum": fields[3]}

def field(text, name):
    m = re.search(rf"^{name}=\(?['\"]?([^'\")\s]*)", text, re.M)
    return m[1] if m else None

errors = []
order = [l.strip() for l in (here / "ORDER").read_text().splitlines() if l.strip() and not l.startswith("#")]
for name in order:
    recipe = here / name / "PKGBUILD"
    if not recipe.is_file():
        errors.append(f"{name}: no PKGBUILD")
        continue
    text = recipe.read_text()
    source = field(text, "source")
    if source is None:  # Yūrei's own files, nothing from upstream
        continue
    pkgver = field(text, "pkgver")
    # a recipe's sources.lock entry: _lockname, else pkgbase, else pkgname
    entry = lock.get(field(text, "_lockname") or field(text, "pkgbase") or field(text, "pkgname"))
    if entry is None:
        errors.append(f"{name}: not in sources.lock")
        continue
    if pkgver != entry["version"]:
        errors.append(f"{name}: version {pkgver}, sources.lock has {entry['version']}")
    if source.replace("$pkgver", pkgver) != entry["url"]:
        errors.append(f"{name}: source {source} isn't {entry['url']}")
    if field(text, "sha256sums") != entry["sum"]:
        errors.append(f"{name}: sum differs from sources.lock")

for e in errors:
    print(e, file=sys.stderr)
print(f"{len(order)} recipes, {len(errors)} problems")
sys.exit(1 if errors else 0)
