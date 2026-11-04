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
    installed = set()

    def runner(command, **kwargs):
        calls.append(command)
        if "info" in command and command[-1] not in installed:
            raise subprocess.CalledProcessError(1, command)
        if "install" in command:
            installed.add(command[-1])
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
    assert set(manifest["installed"]) == {"com.valvesoftware.Steam", "net.lutris.Lutris", "net.davidotek.pupgui2", "com.valvesoftware.Steam.CompatibilityTool.Proton-GE"}


def test_no_selection_does_not_contact_network_or_create_files(tmp_path):
    def runner(*args, **kwargs):
        pytest.fail("No app selection should perform installation")

    assert software.install(tmp_path, [], runner) == 0
    assert list(tmp_path.iterdir()) == []


def test_cached_apps_install_without_network(tmp_path):
    calls = []
    def runner(command, **kwargs):
        calls.append(command)
        assert "info" in command, "Cached app must not contact remotes"
    assert software.install(tmp_path, ["multimedia", "gaming"], runner) == 0
    assert len(calls) == 6
    assert "video/mp4=org.videolan.VLC.desktop" in (tmp_path / "etc/xdg/mimeapps.list").read_text()


def test_pruning_keeps_selected_apps_and_removes_only_known_unselected(tmp_path):
    calls = []
    def runner(command, **kwargs):
        calls.append(command)
    software.prune_unselected(tmp_path, ["gaming"], runner)
    assert [c[-1] for c in calls if "uninstall" in c] == ["org.videolan.VLC"]
    assert not any("com.valvesoftware.Steam" in c for c in calls)


def test_vlc_defaults_preserve_browser_and_file_manager(tmp_path):
    path = tmp_path / "etc/xdg/mimeapps.list"
    path.parent.mkdir(parents=True)
    path.write_text("[Default Applications]\nx-scheme-handler/https=firefox.desktop\ninode/directory=org.kde.dolphin.desktop\n")
    software.set_media_defaults(tmp_path)
    software.set_media_defaults(tmp_path)
    text = path.read_text()
    assert text.count("video/mp4=") == 1
    assert "x-scheme-handler/https=firefox.desktop" in text
    assert "inode/directory=org.kde.dolphin.desktop" in text


@pytest.mark.parametrize("release,accepted", [("ID=yurei\n", True), ("ID=ubuntu\n", False), (None, False)])
def test_main_validates_the_actual_destination_identity(tmp_path, monkeypatch, release, accepted):
    if release is not None:
        path = tmp_path / "usr/lib/os-release"
        path.parent.mkdir(parents=True)
        path.write_text(release)
    monkeypatch.setattr(software.os, "geteuid", lambda: 0, raising=False)
    monkeypatch.setattr(software.subprocess, "run", lambda *a, **kw: subprocess.CompletedProcess(a[0], 0))
    monkeypatch.setattr(software.sys, "argv", ["yurei-software", "--groups", "", "--target-root", str(tmp_path)])
    if accepted:
        assert software.main() == 0
    else:
        with pytest.raises(SystemExit) as error:
            software.main()
        assert error.value.code == 2
