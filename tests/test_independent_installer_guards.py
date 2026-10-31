"""Exercise the backend target checks with command stubs, never real disks."""

import os
import subprocess
import sys
from pathlib import Path

import pytest


pytestmark = pytest.mark.skipif(sys.platform != "linux", reason="backend uses Linux Bash")
SCRIPT = Path(__file__).resolve().parents[1] / "independent/packages/yurei-install/yurei-install"


@pytest.mark.parametrize("changes,accepted", [
    ({}, True),
    ({"TEST_RO": "1"}, False),
    ({"TEST_MOUNTS": "/run/live/medium"}, False),
    ({"TEST_LIVE": "/dev/vda"}, False),
    ({"expected_disk_bytes": "999"}, False),
    ({"expected_disk_device": "8:0"}, False),
    ({"required_bytes": "2000"}, False),
    ({"TEST_TYPE": "part"}, False),
])
def test_target_revalidation(changes, accepted):
    function = "check_target() {" + SCRIPT.read_text(encoding="utf-8").split("check_target() {", 1)[1].split("\nlive_bytes=", 1)[0]
    stubs = r'''
set -euo pipefail
die() { echo "refused: $*"; exit 1; }
live_disk() { printf '%s' "${TEST_LIVE:-}"; }
blockdev() { echo 1000; }
lsblk() {
    case "$*" in
        *MOUNTPOINTS*) printf '%s' "${TEST_MOUNTS:-}" ;;
        *MAJ:MIN*) echo 252:0 ;;
        *TYPE*) echo "${TEST_TYPE:-disk}" ;;
        *RO*) echo "${TEST_RO:-0}" ;;
        *) exit 99 ;;
    esac
}
'''
    env = dict(os.environ, TEST_RO="0", TEST_MOUNTS="", TEST_LIVE="", TEST_TYPE="disk",
               disk="/dev/vda", expected_disk_bytes="1000",
               expected_disk_device="252:0", required_bytes="100")
    env.update(changes)
    result = subprocess.run(["bash", "-c", stubs + function + "\ncheck_target\n"],
                            env=env, capture_output=True, text=True, timeout=5)
    assert (result.returncode == 0) == accepted, result.stdout + result.stderr
    if not accepted:
        assert "refused:" in result.stdout
