"""Remote access rejects TCP listeners, root accounts and empty passwords."""
import importlib.util
from pathlib import Path
import pytest

SOURCE = Path(__file__).resolve().parents[1] / "independent/packages/yurei-hyperv/yurei-hyperv.py"
spec = importlib.util.spec_from_file_location("yurei_hyperv", SOURCE)
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

@pytest.mark.parametrize("port", ["3389", "tcp://:3389", "vsock://-1:3389,tcp://:3389", ""])
def test_rejects_network_or_unspecified_listener(port):
    with pytest.raises(RuntimeError):
        setup.require_vsock("[Globals]\nport=" + port + "\n")

def test_accepts_only_hyperv_socket_listener():
    setup.require_vsock("[Globals]\nport=vsock://-1:3389\n")

@pytest.mark.parametrize("status", ["yurei-remote NP 2026-01-01", "yurei-remote L 2026-01-01", "root P 2026-01-01", ""])
def test_rejects_blank_locked_or_root_passwords(status):
    with pytest.raises(RuntimeError):
        setup.require_password(status)

def test_accepts_password_protected_remote_account():
    setup.require_password("yurei-remote P 2026-01-01 0 99999 7 -1")
