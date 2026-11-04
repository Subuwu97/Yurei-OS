"""Check desktop selection without starting a compositor or touching a disk."""
import os
import subprocess
from pathlib import Path

import pytest


@pytest.mark.skipif(os.name == "nt", reason="requires the distro shell")
def test_plasma_default_and_explicit_labwc_fallback(tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    for name in ["startplasma-wayland", "labwc"]:
        program = bindir / name
        program.write_text("#!/bin/sh\nprintf '%s\\n' '" + name + "'\n")
        program.chmod(0o755)
    launcher = Path(__file__).resolve().parents[1] / "independent/packages/yurei-desktop/yurei-desktop"
    env = dict(os.environ, PATH=str(bindir) + ":" + os.environ["PATH"], WAYLAND_DISPLAY="", XDG_RUNTIME_DIR=str(tmp_path), DBUS_SESSION_BUS_ADDRESS="unix:path=/unused-for-test")
    def run(*args):
        return subprocess.run(["sh", str(launcher), *args], env=env, capture_output=True, text=True)
    result = run()
    assert result.returncode == 0 and result.stdout.strip() == "startplasma-wayland"
    result = run("--labwc")
    assert result.returncode == 0 and result.stdout.strip() == "labwc"
    result = run("--unknown")
    assert result.returncode == 2 and not result.stdout
    (bindir / "startplasma-wayland").unlink()
    result = run("--plasma")
    assert result.returncode == 1 and "not installed" in result.stderr
    result = run()
    assert result.returncode == 0 and result.stdout.strip() == "labwc"
