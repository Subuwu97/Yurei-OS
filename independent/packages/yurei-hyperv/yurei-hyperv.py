#!/usr/bin/env python3
"""Set up Hyper-V-only enhanced sessions; no TCP listener or blank passwords."""
import argparse
import configparser
import os
from pathlib import Path
import subprocess
import sys

USER = "yurei-remote"
MARKER = Path("/var/lib/yurei/hyperv-user")


def require_password(status):
    fields = status.split()
    if len(fields) < 2 or fields[0] != USER or fields[1] != "P":
        raise RuntimeError("The remote account must have a non-empty, unlocked password")


def require_vsock(config):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.read_string(config)
    if parser.get("Globals", "port", fallback="") != "vsock://-1:3389":
        raise RuntimeError("Refusing to enable remote access: the listener is not Hyper-V socket-only")


def enable():
    import grp
    import pwd
    kind = subprocess.check_output(["systemd-detect-virt", "--vm"], text=True).strip()
    if kind != "microsoft":
        raise RuntimeError("This setup is for a Hyper-V guest; it does not enable network remote access")
    require_vsock(Path("/etc/xrdp/xrdp.ini").read_text())
    subprocess.run(["modprobe", "hv_sock"], check=True)
    subprocess.run(["systemd-sysusers", "xrdp.conf"], check=True)
    subprocess.run(["systemd-tmpfiles", "--create", "xrdp.conf"], check=True)
    try:
        account = pwd.getpwnam(USER)
    except KeyError:
        subprocess.run(["useradd", "-m", "-s", "/bin/bash", "-G", "yurei-rdp", USER], check=True)
        MARKER.parent.mkdir(parents=True, exist_ok=True)
        MARKER.write_text(USER + "\n")
        account = pwd.getpwnam(USER)
    if account.pw_uid == 0 or not MARKER.is_file() or MARKER.read_text().strip() != USER:
        raise RuntimeError("An existing account has this name; refusing to alter it")
    print("Set a password for the separate remote desktop account: " + USER, flush=True)
    print("Use this account in Hyper-V Enhanced Session. It is separate from the local desktop.", flush=True)
    subprocess.run(["passwd", USER], check=True)
    require_password(subprocess.check_output(["passwd", "-S", USER], text=True))
    subprocess.run(["usermod", "-aG", "yurei-rdp", USER], check=True)
    directory = Path("/etc/xrdp")
    key = directory / "key.pem"
    certificate = directory / "cert.pem"
    if not key.exists() or not certificate.exists():
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:3072", "-sha256", "-nodes",
                        "-days", "365", "-subj", "/CN=Yurei Hyper-V",
                        "-keyout", str(key), "-out", str(certificate)], check=True)
    os.chown(key, 0, grp.getgrnam("xrdp").gr_gid)
    key.chmod(0o640)
    certificate.chmod(0o644)
    modules = Path("/etc/modules-load.d/yurei-hyperv.conf")
    modules.parent.mkdir(parents=True, exist_ok=True)
    modules.write_text("hv_sock\n")
    subprocess.run(["systemctl", "enable", "--now", "xrdp.service"], check=True)
    print("Enhanced-session services are ready. Remote account: " + USER)
    print("On the Windows host, enable Enhanced Session Mode in Hyper-V settings.")
    print("In an administrator PowerShell window, set your VM's transport:")
    print("Set-VM -VMName '<your VM name>' -EnhancedSessionTransportType HvSocket")
    print("Reconnect using Enhanced Session and leave local audio playback enabled.")
    print("The basic Hyper-V console does not carry audio. Live-session passwords reset on reboot.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("enable", "disable"))
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("Run with sudo")
    try:
        if args.action == "enable":
            enable()
        else:
            subprocess.run(["systemctl", "disable", "--now", "xrdp.service"], check=True)
            Path("/etc/modules-load.d/yurei-hyperv.conf").unlink(missing_ok=True)
            print("Enhanced-session remote access is disabled.")
        result = 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print("Setup did not finish:", error, file=sys.stderr)
        result = 1
    if sys.stdin.isatty():
        input("Press Enter to close. ")
    return result


if __name__ == "__main__":
    sys.exit(main())
