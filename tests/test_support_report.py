"""Check incomplete-system handling and the support report's collection scope."""

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest


SOURCE = Path(__file__).resolve().parents[1] / "independent/packages/yurei-support/yurei-support.py"
spec = importlib.util.spec_from_file_location("yurei_support", SOURCE)
support = importlib.util.module_from_spec(spec)
spec.loader.exec_module(support)


def test_missing_tools_and_system_files_are_normal(tmp_path):
    result = support.collect(tmp_path, runner=lambda args: (False, ""))
    assert result["os"] == {}
    assert result["graphics"] == []
    assert result["packages"] == {}
    assert result["failed_system_service_count"] is None
    assert set(result["services"].values()) == {"unavailable"}


def test_os_release_does_not_execute_shell_or_collect_other_fields(tmp_path):
    (tmp_path / "etc").mkdir()
    (tmp_path / "etc/os-release").write_text(
        'ID=yurei\nPRETTY_NAME="Yurei Linux"\nHOSTNAME=private-host\n'
        'UNRELATED="$(touch should-not-exist)"\n', encoding="utf-8")
    assert support.os_release(tmp_path) == {"ID": "yurei", "PRETTY_NAME": "Yurei Linux"}
    assert not (tmp_path / "should-not-exist").exists()


def test_private_failure_names_and_unrelated_packages_are_not_reported(tmp_path):
    def run(args):
        if args[0] == "pacman":
            return True, "linux 6.18\nprivate-app 1.0\n"
        if "--failed" in args:
            return True, "private-account-worker.service failed\n\n"
        return True, "active\n"

    result = support.collect(tmp_path, runner=run)
    assert result["packages"] == {"linux": "6.18"}
    assert result["failed_system_service_count"] == 1
    assert "private" not in json.dumps(result)


def test_memory_collector_ignores_other_values(tmp_path):
    (tmp_path / "proc").mkdir()
    (tmp_path / "proc/meminfo").write_text("MemTotal: 4096 kB\nMemAvailable: 2048 kB\nOther: 100 kB\n")
    result = support.collect(tmp_path, runner=lambda args: (False, ""))
    assert result["memory_kib"] == {"MemTotal": 4096, "MemAvailable": 2048}


def test_command_timeout_is_unavailable_instead_of_crashing(monkeypatch):
    monkeypatch.setattr(support.shutil, "which", lambda name: "/bin/systemctl")

    def timeout(args, **kwargs):
        raise subprocess.TimeoutExpired(args, 3)

    monkeypatch.setattr(support.subprocess, "run", timeout)
    assert support.command(["systemctl", "--failed"]) == (False, "")


def test_export_never_overwrites_an_existing_file(tmp_path, monkeypatch):
    target = tmp_path / "report.json"
    target.write_text("keep me")
    monkeypatch.setattr(support.platform, "system", lambda: "Linux")
    monkeypatch.setattr(support, "collect", lambda: {})
    monkeypatch.setattr(sys, "argv", ["yurei-support", "--output", str(target)])
    with pytest.raises(SystemExit) as error:
        support.main()
    assert error.value.code == 1
    assert target.read_text() == "keep me"


@pytest.mark.skipif(sys.platform != "linux", reason="actual collector targets Linux")
def test_linux_command_exports_a_real_report(tmp_path):
    target = tmp_path / "linux-report.json"
    result = subprocess.run([sys.executable, str(SOURCE), "--output", str(target)],
                            capture_output=True, text=True, timeout=25)
    assert result.returncode == 0, result.stderr
    report = json.loads(target.read_text(encoding="utf-8"))
    assert report["schema_version"] == 1
    assert report["kernel"]["release"]
    assert set(report["services"]) == set(support.SERVICES)
