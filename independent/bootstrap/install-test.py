#!/usr/bin/env python3
"""Installs Yūrei from the live ISO onto a blank disk in QEMU (UEFI, OVMF),
the way a person would at the live system's console, then starts the
installed system from that disk alone, up to its login prompt.

    sudo iso-test.sh calls it:  install-test.py ISO FIRMWARE OUT-DIR

Talks to the live system over its serial console: logs in as root (no
password on the live system) and runs yurei-install unattended."""

import os
import subprocess
import sys
import time

iso, firmware, out = sys.argv[1:4]
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
            elif self.qemu.poll() is not None:
                return False
            else:
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
def check(what, ok):
    results.append(ok)
    print(("ok   " if ok else "FAIL ") + "install: " + what, flush=True)
    return ok

with open(disk, "wb") as f:
    f.truncate(16 * 1024**3)

print("== install: the live ISO, with a blank 16 GB disk", flush=True)
live = Machine(os.path.join(out, "install-live.log"),
               "-drive", f"file={iso},media=cdrom,readonly=on", "-boot", "d",
               "-drive", f"file={disk},format=raw,if=virtio")
if check("the live system's login prompt", live.wait("yurei-live login:", 300)):
    live.send("root")
    check("logged in", live.wait("# ", 60))
    live.send("YUREI_USER_PASSWORD=test YUREI_ROOT_PASSWORD=test yurei-install --disk /dev/vda "
              "--hostname yurei-installed --user tester --yes "
              "--kernel-options 'console=ttyS0,115200 systemd.tty.term.ttyS0=dumb' "
              "&& echo INSTALL-''DONE || echo INSTALL-''FAILED")
    done = live.wait("INSTALL-DONE", 1800, fail="INSTALL-FAILED")
    check("yurei-install finished", done)
    live.send("poweroff")
live.stop()

if all(results):
    print("== install: the installed system, from the disk alone", flush=True)
    installed = Machine(os.path.join(out, "install-boot.log"),
                        "-drive", f"file={disk},format=raw,if=virtio")
    check("started from the disk, up to its login prompt", installed.wait("yurei-installed login:", 300))
    installed.send("tester")
    installed.wait("Password:", 30)
    installed.send("test")
    check("the user can log in", installed.wait("$ ", 60))
    installed.send("findmnt -no SOURCE,FSTYPE / /boot; echo MOUNTS-''END")
    check("/ and /boot mounted from the disk", installed.wait("MOUNTS-END", 30))
    installed.send("echo test | sudo -S id -u; echo SUDO-''END")
    check("the user is an administrator (sudo)", installed.wait("0\r\nSUDO-END", 30))
    installed.send("exit")
    installed.qemu.kill()
    installed.stop()

os.remove(disk)
sys.exit(0 if results and all(results) else 1)
