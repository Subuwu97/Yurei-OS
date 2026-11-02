import hashlib
import subprocess
import sys
from pathlib import Path


def test_visual_payload_is_reused_without_cachyos_tools(tmp_path):
    root = Path(__file__).resolve().parents[1]
    destination = tmp_path / "assets"
    subprocess.run([sys.executable, str(root / "independent/packages/stage-appearance.py"), str(destination)], check=True)
    original = root / "themes/sddm/yurei"
    for source in original.rglob("*"):
        if source.is_file():
            target = destination / "usr/share/sddm/themes/yurei" / source.relative_to(original)
            assert hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(target.read_bytes()).digest()
    assert (destination / "usr/share/wallpapers/Yurei/metadata.json").is_file()
    assert (destination / "usr/share/plasma/look-and-feel/org.yurei.desktop/metadata.json").is_file()
    assert not (destination / "usr/bin").exists()
    assert not (destination / "etc/sudoers.d").exists()


# Packaging must keep forced first-login layout separate from safe updates.
import os
import pytest


@pytest.mark.skipif(os.name == "nt", reason="requires Linux package tools")
def test_initial_layout_and_updates_have_different_override_policy(tmp_path):
    root = Path(__file__).resolve().parents[1]
    subprocess.run([sys.executable, str(root / "independent/packages/stage-appearance.py"), str(tmp_path / "assets")], check=True)
    payload = tmp_path / "payload"
    payload.mkdir()
    recipe = root / "independent/packages/yurei-appearance/PKGBUILD"
    env = dict(os.environ, RECIPE=str(recipe), startdir=str(tmp_path), pkgdir=str(payload))
    subprocess.run(["bash", "-c", 'source "$RECIPE"; package'], env=env, check=True)
    initial = payload / "usr/share/plasma/look-and-feel/org.yurei.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"
    update = payload / "usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/yurei-desktop-layout.js"
    assert initial.read_text().splitlines()[0] == 'var yureiLayout = "dock";'
    assert update.read_text().splitlines()[0] == 'var yureiLayout = undefined;'
    assert "applications:org.kde.konsole.desktop" in update.read_text()
    assert "applications:org.kde.dolphin.desktop" in update.read_text()
    assert "applications:firefox.desktop" in update.read_text()
    defaults = (payload / "etc/xdg/mimeapps.list").read_text()
    assert "inode/directory=org.kde.dolphin.desktop" in defaults
    assert "x-scheme-handler/https=firefox.desktop" in defaults
    assert "applications:yurei-install-gui.desktop" in update.read_text()
    assert not (payload / "etc/sudoers.d").exists()
