import importlib.machinery
import importlib.util
from pathlib import Path

import pytest

SCRIPT = Path(__file__).parent.parent / "overlay/airootfs/usr/local/bin/yurei-calamares-patch"
loader = importlib.machinery.SourceFileLoader("yurei_calamares_patch", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)


def settings():
    return {
        "modules-search": ["local"],
        "instances": [{"id": "online", "module": "packages", "config": "packages_online.conf"}],
        "sequence": [
            {"show": ["welcome", "partition", "users", "summary"]},
            {"exec": ["partition", "mount", "pacstrap", "users", "bootloader", "umount"]},
            {"show": ["finished"]},
        ],
    }


def test_inserts_step_before_umount():
    s = mod.patch(settings())
    assert s["sequence"][1]["exec"][-2:] == ["shellprocess@yurei", "umount"]
    assert {"id": "yurei", "module": "shellprocess", "config": "shellprocess_yurei.conf"} in s["instances"]
    assert s["instances"][0]["id"] == "online"


def test_is_idempotent():
    s = mod.patch(mod.patch(settings()))
    assert s["sequence"][1]["exec"].count("shellprocess@yurei") == 1
    assert sum(i["id"] == "yurei" for i in s["instances"]) == 1


def test_handles_missing_instances_and_umount():
    s = mod.patch({"sequence": [{"exec": ["partition", "bootloader"]}]})
    assert s["sequence"][0]["exec"] == ["partition", "bootloader", "shellprocess@yurei"]
    assert s["instances"][0]["id"] == "yurei"


def test_rejects_settings_without_exec_phase():
    with pytest.raises(ValueError):
        mod.patch({"sequence": [{"show": ["welcome"]}]})


def test_round_trips_file(tmp_path):
    import yaml
    path = tmp_path / "settings.conf"
    path.write_text(yaml.safe_dump(settings()))
    mod.main(str(path))
    assert "shellprocess@yurei" in yaml.safe_load(path.read_text())["sequence"][1]["exec"]
