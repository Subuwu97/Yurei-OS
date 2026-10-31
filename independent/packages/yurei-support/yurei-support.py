#!/usr/bin/env python3
"""Create a local, read-only system report; never upload it automatically."""

import argparse
import datetime
import json
import os
import platform
import shlex
import shutil
import subprocess
from pathlib import Path


PACKAGES = ("linux", "glibc", "systemd", "pacman", "mesa", "nvidia-utils",
            "qt6-base", "plasma-desktop", "plasma-workspace", "kwin", "sddm",
            "plymouth", "yurei-appearance")
SERVICES = ("sddm.service", "systemd-logind.service", "NetworkManager.service", "iwd.service")


def read(path):
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def command(args):
    if not shutil.which(args[0]):
        return False, ""
    try:
        result = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, timeout=3, check=False)
        return result.returncode == 0, result.stdout
    except (OSError, subprocess.TimeoutExpired):
        return False, ""


def os_release(root):
    result = {}
    text = read(root / "etc/os-release") or read(root / "usr/lib/os-release")
    for line in text.splitlines():
        key, separator, value = line.partition("=")
        if separator and key in ("ID", "VERSION_ID", "PRETTY_NAME"):
            try:
                parts = shlex.split(value, comments=True)
                result[key] = parts[0] if len(parts) == 1 else value
            except ValueError:
                result[key] = "unreadable"
    return result


def collect(root=Path("/"), runner=command):
    report = {
        "schema_version": 1,
        "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "os": os_release(root),
        "kernel": {"release": platform.release(), "architecture": platform.machine()},
        "graphics": [], "displays": [], "memory_kib": {}, "packages": {}, "services": {},
    }
    session = os.environ.get("XDG_SESSION_TYPE", "")
    report["session_type"] = session if session in ("wayland", "x11", "tty") else "unknown"
    drm = root / "sys/class/drm"
    for card in sorted(drm.glob("card[0-9]*")):
        if not card.name[4:].isdigit():
            continue
        driver = card / "device/driver"
        try:
            driver_name = driver.resolve().name if driver.is_symlink() else "unknown"
        except (OSError, RuntimeError):
            driver_name = "unavailable"
        report["graphics"].append({
            "card": card.name,
            "vendor_id": read(card / "device/vendor").strip(),
            "device_id": read(card / "device/device").strip(),
            "driver": driver_name,
        })
    for connector in sorted(drm.glob("card*-*")):
        status = read(connector / "status").strip()
        if status in ("connected", "disconnected", "unknown"):
            report["displays"].append({"connector": connector.name, "status": status})
    for line in read(root / "proc/meminfo").splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[0] in ("MemTotal:", "MemAvailable:") and fields[1].isdigit():
            report["memory_kib"][fields[0].rstrip(":")] = int(fields[1])
    try:
        usage = shutil.disk_usage(root)
        report["root_disk_bytes"] = {"total": usage.total, "free": usage.free}
    except OSError:
        report["root_disk_bytes"] = None
    # Query only named core packages; do not collect the user's full app list.
    _, text = runner(["pacman", "-Q", *PACKAGES])
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0] in PACKAGES:
            report["packages"][parts[0]] = parts[1]
    for service in SERVICES:
        ok, state = runner(["systemctl", "show", service, "--property=ActiveState", "--value", "--no-pager"])
        state = state.strip()
        report["services"][service] = state if ok and state in (
            "active", "inactive", "failed", "activating", "deactivating", "reloading", "maintenance"
        ) else "unavailable"
    ok, failed = runner(["systemctl", "--failed", "--no-legend", "--plain", "--no-pager"])
    report["failed_system_service_count"] = sum(bool(line.strip()) for line in failed.splitlines()) if ok else None
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="save JSON to a new file instead of stdout")
    args = parser.parse_args()
    if platform.system() != "Linux":
        parser.error("run this command inside the Linux system being diagnosed")
    text = json.dumps(collect(), indent=2, ensure_ascii=False) + "\n"
    if args.output:
        try:
            with args.output.open("x", encoding="utf-8") as output:
                output.write(text)
        except OSError as exc:
            parser.exit(1, f"Could not create report: {exc}\n")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
