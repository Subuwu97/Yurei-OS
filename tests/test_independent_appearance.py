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
