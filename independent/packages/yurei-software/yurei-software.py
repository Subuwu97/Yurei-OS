#!/usr/bin/env python3
"""Install explicitly selected app groups into a mounted Yurei system."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

GROUPS = {
    "multimedia": [("VLC and its multimedia codecs", "org.videolan.VLC")],
    "gaming": [("Steam", "com.valvesoftware.Steam"),
               ("Discord", "com.discordapp.Discord"),
               ("Lutris", "net.lutris.Lutris"),
               ("ProtonUp-Qt", "net.davidotek.pupgui2"),
               ("GE-Proton (Flathub build)", "com.valvesoftware.Steam.CompatibilityTool.Proton-GE")],
}


def parse_groups(value):
    groups = value.split(",") if value else []
    if len(groups) != len(set(groups)) or any(group not in GROUPS for group in groups):
        raise ValueError("Choose multimedia, gaming, or multimedia,gaming")
    return groups


def install(root, groups, runner=subprocess.run):
    apps = [app for group in groups for app in GROUPS[group]]
    if not apps:
        return 0
    # Download/cache on the destination disk, not in the live RAM overlay.
    cache = root / "var/cache/flatpak"
    cache.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment.update(FLATPAK_SYSTEM_DIR=str(root / "var/lib/flatpak"),
                       FLATPAK_SYSTEM_CACHE_DIR=str(cache), TMPDIR=str(cache))
    config = "/usr/share/flatpak/remotes.d/flathub.flatpakrepo"
    result = {"requested": groups, "installed": [], "failed": []}
    remote_ready = False
    for title, app_id in apps:
        print("== Installing " + title, flush=True)
        try:
            # Deployments copied from the live ISO work without a network.
            try:
                runner(["flatpak", "--system", "info", app_id], env=environment,
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except subprocess.CalledProcessError:
                if not remote_ready:
                    runner(["flatpak", "--system", "remote-add", "--if-not-exists", "flathub", config],
                           env=environment, check=True)
                    remote_ready = True
                runner(["flatpak", "--system", "install", "--noninteractive", "-y", "flathub", app_id],
                       env=environment, check=True)
                runner(["flatpak", "--system", "info", app_id], env=environment, check=True)
            result["installed"].append(app_id)
        except (OSError, subprocess.CalledProcessError) as error:
            print("Software installation failed:", error, file=sys.stderr)
            result["failed"].append(app_id)
    directory = root / "var/lib/yurei"
    directory.mkdir(parents=True, exist_ok=True)
    temporary = directory / "software.json.tmp"
    temporary.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    temporary.replace(directory / "software.json")
    if result["failed"]:
        print("Optional software is incomplete. Reconnect to the internet and retry the selected group after boot.", file=sys.stderr)
        return 1
    if "org.videolan.VLC" in result["installed"]:
        set_media_defaults(root)
    return 0


def set_media_defaults(root):
    path = root / "etc/xdg/mimeapps.list"
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = path.read_text().splitlines() if path.exists() else []
    types = ("video/mp4", "video/x-matroska", "video/webm", "video/mpeg",
             "audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav")
    lines = [line for line in lines if line.split("=", 1)[0] not in types]
    if "[Default Applications]" not in lines:
        lines += ["[Default Applications]"]
    at = lines.index("[Default Applications]") + 1
    lines[at:at] = [mime + "=org.videolan.VLC.desktop" for mime in types]
    path.write_text("\n".join(lines) + "\n")


def prune_unselected(root, groups, runner=subprocess.run):
    environment = os.environ.copy()
    environment["FLATPAK_SYSTEM_DIR"] = str(root / "var/lib/flatpak")
    if "multimedia" not in groups:
        defaults = root / "etc/xdg/mimeapps.list"
        if defaults.exists():
            defaults.write_text("\n".join(line for line in defaults.read_text().splitlines()
                                          if "=org.videolan.VLC.desktop" not in line) + "\n")
    for group, apps in GROUPS.items():
        if group in groups:
            continue
        for _, app_id in apps:
            try:
                runner(["flatpak", "--system", "info", app_id], env=environment,
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except subprocess.CalledProcessError:
                continue
            runner(["flatpak", "--system", "uninstall", "--noninteractive", "-y", app_id],
                   env=environment, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--groups", required=True)
    parser.add_argument("--target-root", type=Path, default=Path("/"))
    parser.add_argument("--prune-unselected", action="store_true")
    args = parser.parse_args()
    try:
        groups = parse_groups(args.groups)
    except ValueError as error:
        parser.error(str(error))
    root = args.target_root.resolve()
    if os.geteuid() != 0:
        parser.error("Run with sudo to install selected system-wide apps")
    if root != Path("/") and subprocess.run(["mountpoint", "-q", str(root)]).returncode:
        parser.error("The installation destination must be a mounted filesystem")
    release = root / "usr/lib/os-release"
    if not release.is_file() or not any(line in {"ID=yurei", 'ID="yurei"'} for line in release.read_text().splitlines()):
        parser.error("The destination is not a Yurei system")
    if groups and shutil.disk_usage(root).free < 8 * 1024**3:
        parser.error("At least 8 GiB free is required for optional apps and their runtimes")
    if args.prune_unselected:
        prune_unselected(root, groups)
    return install(root, groups)


if __name__ == "__main__":
    sys.exit(main())
