#!/usr/bin/env python3
"""Launch a preinstalled game from its own writable per-user copy.

This launcher ships no game data and downloads nothing. Only verified game
packages should install manifests and payloads under /usr/share/yurei/games.
"""

import argparse
import json
import os
import shutil
import tempfile
from pathlib import Path


GAMES = ("katawa-shoujo", "ddlc")
SEED_ROOT = Path("/usr/share/yurei/games")


def prepare_game(seed_root, data_root, game):
    manifest = json.loads((seed_root / f"{game}.json").read_text(encoding="utf-8"))
    version = manifest.get("version")
    entry = manifest.get("entrypoint")
    if not isinstance(version, str) or not version:
        raise ValueError("game package has no verified version")
    if not isinstance(entry, str) or not entry:
        raise ValueError("game package has no verified entrypoint")
    relative = Path(entry)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("game entrypoint must stay inside the game directory")
    seed = seed_root / game / "payload"
    if not (seed / relative).is_file():
        raise ValueError("the game payload is not installed")
    state = data_root / game
    if state.exists():
        saved = json.loads((state / "source.json").read_text(encoding="utf-8"))
        if saved.get("version") != version:
            raise ValueError("game update needs a migration; existing playthrough was kept")
        # Never recopy a deleted game file: DDLC intentionally changes its own
        # directory as part of a playthrough. Each user keeps independent state.
        if not (state / "payload" / relative).is_file():
            raise ValueError("existing game copy has no launcher; existing playthrough was kept")
        return state / "payload" / relative
    data_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{game}-", dir=data_root) as temporary:
        staged = Path(temporary) / "game"
        staged.mkdir(mode=0o700)
        shutil.copytree(seed, staged / "payload", symlinks=True)
        (staged / "source.json").write_text(json.dumps({"version": version}), encoding="utf-8")
        # Publish only a complete copy. Failed copying leaves no partial game.
        staged.rename(state)
    return state / "payload" / relative


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", choices=GAMES)
    args = parser.parse_args()
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        parser.error("launch games as your desktop user")
    data = os.environ.get("XDG_DATA_HOME")
    base = Path(data) if data and Path(data).is_absolute() else Path.home() / ".local/share"
    try:
        executable = prepare_game(SEED_ROOT, base / "yurei/games", args.game)
        os.chdir(executable.parent)
        os.execv(str(executable), [str(executable)])
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Cannot start {args.game}: {exc}\n")


if __name__ == "__main__":
    main()
