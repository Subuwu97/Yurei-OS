#!/usr/bin/env python3
"""Checks that every recipe in ORDER exists and that each recipe's version,
source address and SHA-256 are the ones in ../bootstrap/sources.lock, so the
packages are built from exactly the sources the bootstrap verified."""

import re
import shlex
import subprocess
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
# A recipe name optionally carries build-only or bootstrap-install.
order = []
for l in (here / "ORDER").read_text().splitlines():
    if l.strip() and not l.startswith("#"):
        words = l.split()
        if len(words) > 2 or (len(words) == 2 and words[1] not in {"build-only", "bootstrap-install"}):
            errors_early = f"ORDER line {l!r}: a name, optionally 'build-only' or 'bootstrap-install'"
            print(errors_early, file=sys.stderr)
            sys.exit(1)
        order.append(words[0])
for name in order:
    recipe = here / name / "PKGBUILD"
    if not recipe.is_file():
        errors.append(f"{name}: no PKGBUILD")
        continue
    text = recipe.read_text()
    syntax = subprocess.run(["bash", "-n", str(recipe)], capture_output=True, text=True)
    if syntax.returncode:
        errors.append(f"{name}: PKGBUILD isn't valid shell: {syntax.stderr.strip()}")
        continue
    source = field(text, "source")
    if source is None:  # YÃ…Â«rei's own files, nothing from upstream
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

# Runtime dependencies must exist in the repository, including split packages.
# Build-only packages are available while compiling but absent from the ISO repo.
def values(text, name):
    match = re.search(rf"^{name}=(\([^)]*\)|[^\n]+)", text, re.M)
    if not match:
        return []
    return shlex.split(match[1].strip().strip("()"), comments=True)

recipes = {
    name: (here / name / "PKGBUILD").read_text()
    for name in order if (here / name / "PKGBUILD").is_file()
}
build_only = {
    line.split()[0] for line in (here / "ORDER").read_text().splitlines()
    if line.strip() and not line.startswith("#")
    and line.split()[-1] == "build-only"
}
repo_names = set()
for name, text in recipes.items():
    if name not in build_only:
        repo_names.update(values(text, "pkgname"))
        repo_names.update(re.split(r"[<>=]", item)[0] for item in values(text, "provides"))
for name, text in recipes.items():
    if name in build_only:
        continue
    for item in values(text, "depends"):
        dependency = re.split(r"[<>=]", item)[0]
        if dependency not in repo_names:
            errors.append(f"{name}: runtime dependency {dependency!r} is absent from the repository")

for e in errors:
    print(e, file=sys.stderr)
print(f"{len(order)} recipes, {len(errors)} problems")
sys.exit(1 if errors else 0)
