"""Installer selections install only requested apps and report partial results."""
import importlib.util
import json
from pathlib import Path
import subprocess

import pytest

SOURCE = Path(__file__).resolve().parents[1] / "independent/packages/yurei-software/yurei-software.py"
spec = importlib.util.spec_from_file_location("yurei_software", SOURCE)
software = importlib.util.module_from_spec(spec)
spec.loader.exec_module(software)


def test_rejects_unknown_and_duplicate_groups():
    for value in ["unknown", "gaming,gaming", "gaming;echo injected", "multimedia,"]:
        with pytest.raises(ValueError):
            software.parse_groups(value)


def test_multimedia_does_not_install_gaming_and_downloads_to_target(tmp_path):
    calls = []

    def runner(command, **kwargs):
        calls.append(command)
        assert kwargs["check"]
        assert kwargs["env"]["FLATPAK_SYSTEM_DIR"] == str(tmp_path / "var/lib/flatpak")
        assert kwargs["env"]["TMPDIR"] == str(tmp_path / "var/cache/flatpak")

    assert software.install(tmp_path, ["multimedia"], runner) == 0
    installs = [command[-1] for command in calls if "install" in command]
    assert installs == ["org.videolan.VLC"]
    manifest = json.loads((tmp_path / "var/lib/yurei/software.json").read_text())
    assert manifest["installed"] == installs
    assert manifest["failed"] == []


def test_failed_app_is_reported_without_losing_successes(tmp_path):
    def runner(command, **kwargs):
        if command[-1] == "com.discordapp.Discord":
            raise subprocess.CalledProcessError(1, command)

    assert software.install(tmp_path, ["gaming"], runner) == 1
    manifest = json.loads((tmp_path / "var/lib/yurei/software.json").read_text())
    assert manifest["failed"] == ["com.discordapp.Discord"]
    assert set(manifest["installed"]) == {"com.valvesoftware.Steam", "net.lutris.Lutris", "net.davidotek.pupgui2"}


def test_no_selection_does_not_contact_network_or_create_files(tmp_path):
    def runner(*args, **kwargs):
        pytest.fail("No app selection should perform installation")

    assert software.install(tmp_path, [], runner) == 0
    assert list(tmp_path.iterdir()) == []
