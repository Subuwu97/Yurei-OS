#!/usr/bin/env python3
"""Installs Yūrei from the live ISO onto a blank disk in QEMU (UEFI, OVMF),
the way a person would at the live system's console, then starts the
installed system from that disk alone, up to its login prompt.

    sudo iso-test.sh calls it:  install-test.py ISO FIRMWARE OUT-DIR

Talks to the live system over its serial console: logs in as root (no
password on the live system) and runs yurei-install unattended."""

import argparse
import base64
import hashlib
import json
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("iso")
parser.add_argument("firmware")
parser.add_argument("out")
parser.add_argument("--backend", type=Path, help="inject this backend into the live VM's RAM")
parser.add_argument("--gui-protocol", action="store_true", help="test the GUI's stdin-password/device-binding protocol")
parser.add_argument("--disk-size-gib", type=int, default=16)
parser.add_argument("--expected-session", choices=("greeter", "console"), default="greeter")
args = parser.parse_args()
iso, firmware, out = args.iso, args.firmware, args.out
if not 16 <= args.disk_size_gib <= 128:
    parser.error("the disposable disk must be between 16 and 128 GiB")
os.makedirs(out, exist_ok=True)
password = "yurei-test-pass" if args.gui_protocol else "test"
disk = os.path.join(out, "install-disk.img")
accel = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]


class Machine:
    def __init__(self, log, *args):
        self.log = open(log, "wb")
        self.seen = b""
        self.qemu = subprocess.Popen(
            ["qemu-system-x86_64", *accel, "-m", "3072", "-smp", "2", "-bios", firmware,
             "-display", "none", "-serial", "stdio", "-monitor", "none", "-no-reboot",
             "-nic", "user,model=virtio-net-pci", *args],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        os.set_blocking(self.qemu.stdout.fileno(), False)

    def wait(self, text, timeout, fail=None):
        """Waits for text on the console; True if it came, False if the
        fail text came first or time ran out."""
        end = time.time() + timeout
        while time.time() < end:
            data = self.qemu.stdout.read()
            if data:
                self.log.write(data)
                self.log.flush()
                self.seen += data
            if fail and fail.encode() in self.seen:
                return False
            if text.encode() in self.seen:
                self.seen = self.seen[self.seen.index(text.encode()) + len(text):]
                return True
            if self.qemu.poll() is not None:
                return False
            if not data:
                time.sleep(0.5)
        return False

    def send(self, line):
        self.qemu.stdin.write(line.encode() + b"\n")
        self.qemu.stdin.flush()

    def stop(self, timeout=60):
        try:
            self.qemu.wait(timeout)
        except subprocess.TimeoutExpired:
            self.qemu.kill()
            self.qemu.wait()
        self.log.close()


results = []
checks = []
def check(what, ok):
    results.append(ok)
    checks.append({"check": what, "passed": bool(ok)})
    print(("ok   " if ok else "FAIL ") + "install: " + what, flush=True)
    return ok

with open(disk, "xb") as f:
    f.truncate(args.disk_size_gib * 1024**3)

print(f"== install: the live ISO, with a blank {args.disk_size_gib} GiB disk", flush=True)
live = Machine(os.path.join(out, "install-live.log"),
               "-drive", f"file={iso},media=cdrom,readonly=on", "-boot", "d",
               "-drive", f"file={disk},format=raw,if=virtio")
if check("the live system's login prompt", live.wait("yurei-live login:", 300)):
    live.send("root")
    if check("logged in", live.wait("# ", 60)):
        # Stop echoing injected source and establish an unambiguous prompt.
        live.send("stty -echo; export PS1='yurei-''test> '")
        ready = check("serial command channel ready", live.wait("yurei-test> ", 30))
        backend = "yurei-install"
        if ready and args.backend:
            source = args.backend.read_bytes()
            digest = hashlib.sha256(source).hexdigest()
            encoded = base64.b64encode(source).decode("ascii")
            live.send(": > /run/yurei-backend.b64")
            ready = live.wait("yurei-test> ", 30)
            for offset in range(0, len(encoded), 768):
                if not ready:
                    break
                live.send("printf '%s' '" + encoded[offset:offset + 768] + "' >> /run/yurei-backend.b64")
                ready = live.wait("yurei-test> ", 30)
            backend = "/run/yurei-install-under-test"
            live.send(f"base64 -d /run/yurei-backend.b64 > {backend} && chmod 700 {backend} && "
                      f"echo '{digest}  {backend}' | sha256sum -c - && echo BACKEND-''READY || echo BACKEND-''BAD")
            ready = check("injected backend matches the reviewed source", ready and live.wait("BACKEND-READY", 60, fail="BACKEND-BAD"))
        if ready:
            command = backend + " --disk /dev/vda --hostname yurei-installed --user tester --yes "
            command += "--kernel-options 'console=ttyS0,115200 systemd.tty.term.ttyS0=dumb' "
            if args.gui_protocol:
                command += f'--passwords-stdin --expected-disk-bytes {args.disk_size_gib * 1024**3} '
                command += '--expected-disk-device "$(lsblk -dn -o MAJ:MIN /dev/vda | tr -d \' \')" '
                command = "printf '%s\\n' " + shlex.quote(password) + " " + shlex.quote(password) + " | " + command
            else:
                command = "YUREI_USER_PASSWORD=test YUREI_ROOT_PASSWORD=test " + command
            live.send(command + "&& echo INSTALL-''DONE || echo INSTALL-''FAILED")
            check("yurei-install finished", live.wait("INSTALL-DONE", 1800, fail="INSTALL-FAILED"))
    live.send("poweroff")
live.stop()

if all(results):
    print("== install: the installed system, from the disk alone", flush=True)
    installed = Machine(os.path.join(out, "install-boot.log"),
                        "-drive", f"file={disk},format=raw,if=virtio")
    check("started from the disk, up to its login prompt", installed.wait("yurei-installed login:", 300))
    installed.send("tester")
    installed.wait("Password:", 30)
    installed.send(password)
    check("the user can log in", installed.wait("$ ", 60))
    installed.send("if [ \"$(findmnt -nro MAJ:MIN /)\" = \"$(lsblk -dn -o MAJ:MIN /dev/vda2 | tr -d ' ')\" ] && "
                   "[ \"$(findmnt -nro MAJ:MIN /boot)\" = \"$(lsblk -dn -o MAJ:MIN /dev/vda1 | tr -d ' ')\" ]; "
                   "then echo MOUNTS-''OK; else echo MOUNTS-''BAD; fi")
    check("/ and /boot mounted from the installed disk", installed.wait("MOUNTS-OK", 30, fail="MOUNTS-BAD"))
    installed.send("if [ \"$(printf '%s\\n' " + shlex.quote(password) + " | sudo -S id -u)\" = 0 ]; "
                   "then echo SUDO-''OK; else echo SUDO-''BAD; fi")
    check("the user is an administrator (sudo)", installed.wait("SUDO-OK", 30, fail="SUDO-BAD"))
    if args.expected_session == "greeter":
        installed.send("if id -nG | grep -qw seat && systemctl -q is-enabled seatd yurei-greeter; then echo GREETER-''OK; else echo GREETER-''BAD; fi")
        check("the user has the seat, and the login screen is on", installed.wait("GREETER-OK", 30, fail="GREETER-BAD"))
    else:
        installed.send("if [ \"$(systemctl get-default)\" = multi-user.target ]; then echo CONSOLE-''OK; else echo CONSOLE-''BAD; fi")
        check("older seed image retains console boot", installed.wait("CONSOLE-OK", 30, fail="CONSOLE-BAD"))
    installed.send("exit")
    installed.qemu.kill()
    installed.stop()

os.remove(disk)
Path(out, "install-result.json").write_text(json.dumps({
    "iso": Path(iso).name, "backend_sha256": hashlib.sha256(args.backend.read_bytes()).hexdigest() if args.backend else None,
    "gui_protocol": args.gui_protocol, "disposable_disk_gib": args.disk_size_gib,
    "expected_session": args.expected_session, "checks": checks,
}, indent=2) + "\n", encoding="utf-8")
sys.exit(0 if results and all(results) else 1)
