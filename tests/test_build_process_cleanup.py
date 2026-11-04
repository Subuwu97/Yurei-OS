"""The build and WSL host can have accounts with the same numeric UID."""
import importlib.util
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / "independent/bootstrap/cleanup-build-processes.py"


def test_cleanup_requires_both_build_root_and_all_builder_uids(tmp_path):
    spec = importlib.util.spec_from_file_location("build_cleanup", MODULE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    build_root = tmp_path / "build-root"
    build_root.mkdir()
    process = tmp_path / "123"
    process.mkdir()
    (process / "root").mkdir()
    (process / "status").write_text("Name:\tgpg-agent\nUid:\t1000\t1000\t1000\t1000\n")
    # Same numeric UID alone is never sufficient (including another root).
    assert not module.belongs_to_build(process, 1000, build_root.stat())
    assert module.belongs_to_build(process, 1000, (process / "root").stat())
    assert not module.belongs_to_build(process, 1001, (process / "root").stat())
    (process / "status").write_text("Uid:\t1000\t0\t1000\t1000\n")
    assert not module.belongs_to_build(process, 1000, (process / "root").stat())
    (process / "status").unlink()
    assert not module.belongs_to_build(process, 1000, (process / "root").stat())
