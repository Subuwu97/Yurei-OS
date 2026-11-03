"""Exercise the installer's mount isolation inside a disposable namespace."""
import os
from pathlib import Path
import shutil
import subprocess

import pytest


@pytest.mark.skipif(os.name != "posix", reason="requires Linux mount namespaces")
def test_target_cleanup_preserves_live_submounts(tmp_path):
    if not shutil.which("unshare") or not shutil.which("mount"):
        pytest.skip("mount namespace tools unavailable")
    prefix = [] if os.geteuid() == 0 else ["sudo", "-n"]
    if prefix and subprocess.run(prefix + ["true"], capture_output=True).returncode:
        pytest.skip("requires root in a disposable mount namespace")
    installer = (Path(__file__).resolve().parents[1] / "independent/packages/yurei-install/yurei-install").read_text(encoding="utf-8")
    start = installer.index("for fs in proc sys dev; do")
    setup = installer[start:installer.index("\ndone", start) + len("\ndone")]
    # Use fixture filesystems instead of the namespace's actual /dev and /sys.
    setup = setup.replace('"/$fs"', '"$source/$fs"')
    program = r'''
set -euo pipefail
mount --make-rprivate /
scratch=$1
mount -t tmpfs tmpfs "$scratch"
source=$scratch/live
target=$scratch/target
mkdir -p "$source" "$target"
for fs in proc sys dev; do
    mkdir -p "$source/$fs" "$target/$fs"
    mount -t tmpfs tmpfs "$source/$fs"
    mount --make-shared "$source/$fs"
    mkdir "$source/$fs/child"
    mount -t tmpfs tmpfs "$source/$fs/child"
done
''' + setup + r'''
for fs in dev sys proc; do
    umount -R "$target/$fs"
    mountpoint -q "$source/$fs/child"
done
'''
    result = subprocess.run(prefix + ["unshare", "--mount", "--fork", "bash", "-c", program, "mount-test", str(tmp_path)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
