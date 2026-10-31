#!/usr/bin/env python3
"""Check literal top-level PKGBUILD dependencies without executing recipes.

Ordering is enforced after ORDER's install marker: earlier bootstrap recipes
build against the pre-existing chroot. Package-specific function metadata and
version compatibility are left to makepkg/pacman and the installed-root check.
"""

import re
import shlex
import sys
from pathlib import Path


# Built from pinned sources by base2-inside.sh before any package recipe runs.
# These are allowed only as build dependencies, never as runtime dependencies.
BOOTSTRAP_BUILD_TOOLS = {"meson", "ninja"}
INSTALL_MARKER = "#> install from here on"


def metadata(text, key):
    matches = list(re.finditer(rf"^{key}=(\((.*?)\)|([^\n]+))", text, re.M | re.S))
    if len(matches) > 1:
        raise ValueError(f"multiple top-level {key} assignments")
    if not matches:
        return []
    match = matches[0]
    values = shlex.split(match[2] if match[2] is not None else match[3], comments=True)
    # Dependency versions may use $pkgver, but package names must be literal.
    names = [re.split(r"[<>=]", value, maxsplit=1)[0] for value in values]
    if any(not re.fullmatch(r"[A-Za-z0-9@._+-]+", name) for name in names):
        raise ValueError(f"{key} must use literal package names")
    return names


def validate(root):
    errors, entries, seen = [], [], set()
    installed_stage = False
    for number, raw in enumerate((root / "ORDER").read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if line == INSTALL_MARKER:
            installed_stage = True
        if not line or line.startswith("#"):
            continue
        words = line.split()
        if len(words) > 2 or (len(words) == 2 and words[1] != "build-only"):
            errors.append(f"ORDER:{number}: expected NAME [build-only]")
            continue
        name = words[0]
        if name in seen:
            errors.append(f"ORDER:{number}: duplicate recipe {name}")
            continue
        if not re.fullmatch(r"[A-Za-z0-9@._+-]+", name):
            errors.append(f"ORDER:{number}: invalid recipe name")
            continue
        seen.add(name)
        entries.append((name, len(words) == 2, installed_stage))
    if not installed_stage:
        errors.append("ORDER: missing install marker; dependency ordering would not be checked")

    recipes, providers = {}, {}
    for index, (name, build_only, enforce_order) in enumerate(entries):
        try:
            text = (root / name / "PKGBUILD").read_text(encoding="utf-8")
            fields = {key: metadata(text, key) for key in ("pkgname", "provides", "depends", "makedepends")}
            if not fields["pkgname"]:
                raise ValueError("missing top-level pkgname")
            recipes[name] = fields
            for package in fields["pkgname"] + fields["provides"]:
                provider = providers.get(package)
                if provider and provider[1] != name:
                    errors.append(f"{name}: ambiguous provider for {package} (also {provider[1]})")
                else:
                    providers[package] = (index, name, build_only)
        except (OSError, ValueError) as exc:
            errors.append(f"{name}: {exc}")

    for index, (name, _, enforce_order) in enumerate(entries):
        for kind in ("depends", "makedepends"):
            for dependency in recipes.get(name, {}).get(kind, []):
                provider = providers.get(dependency)
                if provider is None:
                    if kind == "makedepends" and dependency in BOOTSTRAP_BUILD_TOOLS:
                        continue
                    errors.append(f"{name}: {kind} {dependency} has no provider in ORDER")
                elif kind == "depends" and provider[2]:
                    errors.append(f"{name}: runtime dependency {dependency} is build-only")
                elif enforce_order and provider[0] > index:
                    errors.append(f"{name}: {kind} {dependency} must come earlier in ORDER ({provider[1]})")
    return len(entries), errors


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
    count, errors = validate(root)
    for error in errors:
        print(error, file=sys.stderr)
    print(f"{count} recipes: {len(errors)} dependency/order problems")
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
