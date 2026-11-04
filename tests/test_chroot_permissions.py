"""Entering a packaged root must preserve privileged helper permissions."""
import os
from pathlib import Path
import shutil
import subprocess

import pytest


@pytest.mark.skipif(os.name != "posix", reason="requires Linux file ownership semantics")
def test_app_preload_entry_preserves_root_owned_setuid_helper(tmp_path):
    prefix = [] if os.geteuid() == 0 else ["sudo", "-n"]
    if prefix and (not shutil.which("sudo") or subprocess.run(prefix + ["true"], capture_output=True).returncode):
        pytest.skip("requires root for the disposable ownership fixture")
    root = tmp_path / "root"
    (root / "usr/bin").mkdir(parents=True)
    for name in ("bash", "gcc", "sudo"):
        program = root / "usr/bin" / name
        program.write_text("fixture\n")
        program.chmod(0o755)
    commands = tmp_path / "commands"
    commands.mkdir()
    # Exercise the real entrypoint and ownership operations, but never mount
    # anything or execute the fixture's placeholder binaries.
    for name in ("mount", "umount", "mountpoint", "chroot"):
        stub = commands / name
        stub.write_text("#!/bin/sh\nexit " + ("1" if name == "mountpoint" else "0") + "\n")
        stub.chmod(0o755)
    source = Path(__file__).resolve().parents[1] / "independent/bootstrap/chroot.sh"
    program = r'''
set -eu
root=$1
commands=$2
source=$3
chown 0:0 "$root/usr/bin/sudo"
chmod 4755 "$root/usr/bin/sudo"
PATH="$commands:$PATH" YUREI="$root" SOURCES="$commands" bash "$source" apps-inside.sh
test "$(stat -c '%u:%a' "$root/usr/bin/sudo")" = 0:4755
'''
    try:
        result = subprocess.run(prefix + ["bash", "-c", program, "permission-test", str(root), str(commands), str(source)],
                                capture_output=True, text=True, timeout=30)
    finally:
        if prefix:
            subprocess.run(prefix + ["chown", "-R", f"{os.getuid()}:{os.getgid()}", str(root)], check=True)
    assert result.returncode == 0, result.stdout + result.stderr
