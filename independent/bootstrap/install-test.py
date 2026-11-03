#!/usr/bin/env python3
"""Installs YÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â«rei from the live ISO onto a blank disk in QEMU (UEFI, OVMF),
the way a person would at the live system's console, then starts the
installed system from that disk alone, up to its login prompt.

    sudo iso-test.sh calls it:  install-test.py ISO FIRMWARE OUT-DIR

Talks to the live system over its serial console: logs in as root (no
password on the live system) and runs yurei-install unattended."""

import argparse
import atexit
import base64
import hashlib
import json
import os
import shlex
import socket
import subprocess
import sys
import time
import wave
import struct
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("iso")
parser.add_argument("firmware")
parser.add_argument("out")
parser.add_argument("--backend", type=Path, help="inject this backend into the live VM's RAM")
parser.add_argument("--gui-protocol", action="store_true", help="test the GUI's stdin-password/device-binding protocol")
parser.add_argument("--gui-preview-check", action="store_true", help="render the installed GUI in the live guest before installation")
parser.add_argument("--disk-size-gib", type=int, default=16)
parser.add_argument("--expected-session", choices=("greeter", "console", "sddm"), default="greeter")
parser.add_argument("--desktop-check", action="store_true", help="verify real KWin/Plasma startup and SDDM login in the disposable VM")
args = parser.parse_args()
iso, firmware, out = args.iso, args.firmware, args.out
audio_enabled = args.desktop_check
if not 16 <= args.disk_size_gib <= 128:
    parser.error("the disposable disk must be between 16 and 128 GiB")
os.makedirs(out, exist_ok=True)
password = "yurei-test-pass" if args.gui_protocol else "test"
disk = os.path.join(out, "install-disk.img")
accel = ["-enable-kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) else ["-cpu", "max"]


machines = []


def cleanup_machines():
    for machine in machines:
        if machine.qemu.poll() is None:
            machine.qemu.kill()
            machine.qemu.wait()
        machine.log.close()


atexit.register(cleanup_machines)


class Machine:
    def __init__(self, log, *args):
        self.log = open(log, "wb")
        self.seen = b""
        self.qmp_path = log + ".qmp"
        if os.path.exists(self.qmp_path):
            os.unlink(self.qmp_path)
        self.audio_path = log + ".wav"
        audio_devices = [
            "-audiodev", f"wav,id=yureiaudio,path={self.audio_path},out.frequency=8000,out.channels=1,out.format=s16",
            "-device", "intel-hda,id=yureihda", "-device", "hda-duplex,bus=yureihda.0,audiodev=yureiaudio",
        ] if audio_enabled else []
        self.qemu = subprocess.Popen(
            ["qemu-system-x86_64", *accel, "-m", "4096", "-smp", "2", "-bios", firmware,
             "-display", "none", "-vga", "virtio", "-serial", "stdio", "-monitor", "none", "-no-reboot",
             "-qmp", f"unix:{self.qmp_path},server=on,wait=off",
             "-nic", "user,model=virtio-net-pci", *audio_devices, *args],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        machines.append(self)
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

    def monitor(self, command, arguments):
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(30)
            connection.connect(self.qmp_path)
            stream = connection.makefile("rwb")
            json.loads(stream.readline())
            for name, data in [("qmp_capabilities", {}), (command, arguments)]:
                stream.write((json.dumps({"execute": name, "arguments": data}) + "\n").encode())
                stream.flush()
                while True:
                    response = json.loads(stream.readline())
                    if "error" in response:
                        raise RuntimeError(response["error"])
                    if "return" in response:
                        break

    def screenshot(self, name):
        self.monitor("screendump", {"filename": os.path.abspath(os.path.join(out, name)), "format": "png"})

    def type_password(self, value):
        # Test-only password sent to the selected SDDM password field.
        for char in value:
            key = "minus" if char == "-" else char
            self.monitor("human-monitor-command", {"command-line": "sendkey " + key})
            time.sleep(0.12)
        self.monitor("human-monitor-command", {"command-line": "sendkey ret"})

    def send(self, line):
        self.qemu.stdin.write(line.encode() + b"\n")
        self.qemu.stdin.flush()

    def stop(self, timeout=180):
        # Keep stdin open until the guest exits: EOF on the stdio chardev can
        # race the last serial command. Drain output throughout shutdown.
        deadline = time.monotonic() + timeout
        while self.qemu.poll() is None and time.monotonic() < deadline:
            data = self.qemu.stdout.read()
            if data:
                self.log.write(data)
                self.log.flush()
            else:
                time.sleep(0.05)
        graceful = self.qemu.poll() is not None
        if not graceful:
            print("VM shutdown timed out; terminating QEMU", flush=True)
            try:
                self.screenshot(Path(self.log.name).stem + "-shutdown-timeout.png")
            except (OSError, RuntimeError) as error:
                print("Could not capture shutdown screen:", error, flush=True)
            self.qemu.kill()
        self.qemu.wait()
        os.set_blocking(self.qemu.stdout.fileno(), True)
        self.log.write(self.qemu.stdout.read())
        self.qemu.stdout.close()
        self.qemu.stdin.close()
        self.log.close()
        return graceful and self.qemu.returncode == 0


results = []
checks = []
def check(what, ok):
    results.append(ok)
    checks.append({"check": what, "passed": bool(ok)})
    print(("ok   " if ok else "FAIL ") + "install: " + what, flush=True)
    return ok

def request_shutdown(machine, label, password=None):
    command = "systemctl --no-block poweroff"
    if password is not None:
        command = "printf '%s\\n' " + shlex.quote(password) + " | sudo -S " + command
    machine.send(command + "; rc=$?; if [ $rc -eq 0 ]; then echo SHUTDOWN-''ACCEPTED; else echo SHUTDOWN-''REJECTED-$rc; fi")
    accepted = machine.wait("SHUTDOWN-ACCEPTED", 30, fail="SHUTDOWN-REJECTED")
    if not accepted and machine.qemu.poll() == 0:
        # A fast shutdown may end the serial session before the acknowledgement.
        accepted = True
    if not accepted and machine.qemu.poll() is None:
        machine.send("systemctl list-jobs --no-pager; systemd-inhibit --list --no-pager; journalctl -b -n 80 --no-pager; echo SHUTDOWN-DIAG-''DONE")
        machine.wait("SHUTDOWN-DIAG-DONE", 30)
    return check(label + " accepted the systemd shutdown request", accepted)


def check_network_agent(machine, label):
    # No radio is attached to this VM; verify the actual Plasma secret agent
    # loads, without claiming that this exercises a wireless association.
    machine.send("for n in $(seq 1 30); do if busctl --user call org.kde.kded6 /kded org.kde.kded6 loadedModules 2>/dev/null | grep -q '\"networkmanagement\"'; then echo NETWORK-AGENT-''READY; break; fi; sleep 1; done")
    ok = check(label + " loads the Plasma Wi-Fi secret agent", machine.wait("NETWORK-AGENT-READY", 45))
    if not ok:
        machine.send("systemctl --user status plasma-kded6 --no-pager; journalctl --user -b -n 80 --no-pager; echo NETWORK-DIAG-''DONE")
        machine.wait("NETWORK-DIAG-DONE", 30)
    return ok


def check_audio(machine, label):
    machine.send("for n in $(seq 1 60); do if pactl info >/dev/null 2>&1 && wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q alsa_output; then echo AUDIO-SINK-''READY; break; fi; sleep 1; done")
    ok = check(label + " detects an ALSA output through PipeWire", machine.wait("AUDIO-SINK-READY", 90))
    if ok:
        program = "import math,struct,wave;w=wave.open('/tmp/yurei-tone.wav','wb');w.setparams((1,2,48000,0,'NONE','not compressed'));w.writeframes(b''.join(struct.pack('<h',int(12000*math.sin(2*math.pi*440*n/48000))) for n in range(48000)));w.close()"
        machine.send("python3 -c " + shlex.quote(program) + " && wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 && wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5 && timeout 15 paplay /tmp/yurei-tone.wav && echo AUDIO-PLAY-''OK || echo AUDIO-PLAY-''BAD")
        ok = check(label + " plays a tone through PulseAudio compatibility", machine.wait("AUDIO-PLAY-OK", 45, fail="AUDIO-PLAY-BAD"))
    if not ok:
        machine.send("cat /proc/asound/cards; wpctl status; systemctl --user status pipewire pipewire-pulse wireplumber --no-pager; journalctl --user -u pipewire -u pipewire-pulse -u wireplumber -n 60 --no-pager; echo AUDIO-DIAG-''DONE")
        machine.wait("AUDIO-DIAG-DONE", 45)
    return ok


def check_recorded_audio(machine, label):
    try:
        maximum = 0
        with wave.open(machine.audio_path, "rb") as recording:
            if recording.getsampwidth() != 2:
                raise ValueError("Unexpected capture sample format")
            while data := recording.readframes(65536):
                maximum = max(maximum, max((abs(v[0]) for v in struct.iter_unpack("<h", data)), default=0))
        check(label + " delivered non-silent PCM to the emulated sound device", maximum > 300)
    except (OSError, EOFError, wave.Error, ValueError) as error:
        print("Audio capture error:", error, flush=True)
        check(label + " captured sound output", False)


def check_browser(machine, label):
    # Serve an actual HTTP document: an instant data: navigation can race
    # Firefox's headless screenshot listener. Keep the normal browser sandbox.
    program = """import functools, http.server, pathlib, subprocess, tempfile, threading
with tempfile.TemporaryDirectory(prefix='yurei-browser-') as temporary:
    root = pathlib.Path(temporary)
    (root / 'index.html').write_text('<!doctype html><html><body><h1>Yurei Firefox test</h1></body></html>')
    profile = root / 'profile'
    profile.mkdir()
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=temporary)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        image = root / 'browser.png'
        result = subprocess.run(['firefox', '--headless', '--no-remote', '--profile', str(profile), '--window-size=800,600', '--screenshot', str(image), 'http://127.0.0.1:%d/index.html' % server.server_port], timeout=90)
        print('Firefox exit status:', result.returncode, flush=True)
        assert result.returncode == 0
        data = image.read_bytes()
        assert data[:8] == bytes.fromhex('89504e470d0a1a0a') and len(data) > 100
        assert int.from_bytes(data[16:20], 'big') == 800 and int.from_bytes(data[20:24], 'big') == 600
    finally:
        server.shutdown()
        server.server_close()
"""
    encoded = base64.b64encode(program.encode()).decode()
    command = "python3 -c " + shlex.quote("import base64;exec(base64.b64decode(" + repr(encoded) + "))")
    machine.send(command + " && echo BROWSER-''OK || echo BROWSER-''BAD")
    ok = check(label + " Firefox renders a local HTTP page without sandbox overrides", machine.wait("BROWSER-OK", 120, fail="BROWSER-BAD"))
    if not ok:
        machine.send("ldd /usr/lib/firefox/libxul.so | grep 'not found'; free -m; journalctl -k -n 30 --no-pager; echo BROWSER-DIAG-''DONE")
        machine.wait("BROWSER-DIAG-DONE", 45)
    return ok


with open(disk, "xb") as f:
    f.truncate(args.disk_size_gib * 1024**3)
def cleanup_test_disk():
    cleanup_machines()
    if os.path.exists(disk):
        os.remove(disk)


atexit.register(cleanup_test_disk)

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
        if ready:
            # Exercise timedated over D-Bus in the disposable live VM. Disable
            # NTP before setting time, then restore it after the manual check.
            live.send("if timedatectl set-ntp false && "
                      "timedatectl set-timezone America/Chicago && "
                      "[ \"$(timedatectl show -p Timezone --value)\" = America/Chicago ] && "
                      "timedatectl set-timezone Etc/UTC && "
                      "timedatectl set-time \"$(date -u '+%Y-%m-%d %H:%M:%S')\" && "
                      "timedatectl set-ntp true; then echo CLOCK-''OK; "
                      "else journalctl -u systemd-timedated --no-pager -n 30; echo CLOCK-''BAD; fi")
            ready = check("live clock and timezone can be changed through timedated", live.wait("CLOCK-OK", 60, fail="CLOCK-BAD"))
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
        if ready and args.desktop_check:
            live.send("for n in $(seq 1 120); do if pgrep -xu 0 plasmashell >/dev/null && pgrep -xu 0 kwin_wayland >/dev/null; then echo LIVE-''DESKTOP-OK; break; fi; sleep 1; done")
            ready = check("live KWin and Plasma desktop started", live.wait("LIVE-DESKTOP-OK", 150))
            live.screenshot("live-plasma.png")
            if not ready:
                live.send("journalctl -b --no-pager -n 120; journalctl --user -b --no-pager -n 120; echo DESKTOP-DIAG-''DONE")
                live.wait("DESKTOP-DIAG-DONE", 60)
        if ready and args.desktop_check:
            live.send("if grep -qx 'Enabled=false' /etc/xdg/kwalletrc; then echo LIVE-WALLET-''OK; else echo LIVE-WALLET-''BAD; fi")
            ready = check("live Wi-Fi does not require an encrypted wallet", live.wait("LIVE-WALLET-OK", 30, fail="LIVE-WALLET-BAD"))
            ready = check_network_agent(live, "live session") and ready
        if ready and args.desktop_check:
            ready = check_audio(live, "live session")
            if ready:
                ready = check_browser(live, "live session")
        if ready and args.gui_preview_check:
            # Execute Yurei's own binary and Qt libraries, not the host's Qt.
            # Offscreen preview does not inventory disks or launch the backend.
            live.send("mkdir -p /run/yurei-gui-check && "
                      "for page in 0 1 2 3 4 5 6; do "
                      "QT_QPA_PLATFORM=offscreen /usr/bin/yurei-install-gui --preview "
                      "--page \"$page\" --screenshot /run/yurei-gui-check/page-$page.png "
                      "&& test -s /run/yurei-gui-check/page-$page.png || break; "
                      "done; "
                      "if [ \"$(find /run/yurei-gui-check -name 'page-*.png' -size +0c | wc -l)\" -eq 7 ]; "
                      "then echo GUI-''READY; else echo GUI-''FAILED; fi")
            ready = check("all seven GUI previews render with the live image's Qt", live.wait("GUI-READY", 180, fail="GUI-FAILED"))
        if ready:
            # Save mount identities to detect propagation damage from chroot
            # cleanup, rather than discovering it only at guest shutdown.
            mount_probe = "for path in /proc /sys /sys/fs/cgroup /dev /dev/pts /dev/shm; do findmnt -n -o ID,TARGET --mountpoint \"$path\" || exit 1; done"
            live.send("bash -c " + shlex.quote(mount_probe) + " > /tmp/yurei-mounts-before && echo MOUNT-BASELINE-''OK || echo MOUNT-BASELINE-''BAD")
            ready = check("live mounts recorded before installation", live.wait("MOUNT-BASELINE-OK", 30, fail="MOUNT-BASELINE-BAD"))
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
            live.send("bash -c " + shlex.quote(mount_probe) + " > /tmp/yurei-mounts-after && diff -u /tmp/yurei-mounts-before /tmp/yurei-mounts-after && systemd-run --wait --pipe /usr/bin/true && echo LIVE-INTEGRITY-''OK || { cat /proc/self/mountinfo; journalctl -b -n 100 --no-pager; echo LIVE-INTEGRITY-''BAD; }")
            check("installer preserves live mounts and systemd service execution", live.wait("LIVE-INTEGRITY-OK", 60, fail="LIVE-INTEGRITY-BAD"))
    request_shutdown(live, "live VM")
check("live VM shut down cleanly", live.stop())
if audio_enabled:
    check_recorded_audio(live, "live session")

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
    if args.expected_session == "sddm":
        installed.send("if ! grep -qw nullok /etc/pam.d/login && [ ! -e /etc/systemd/system/getty@tty1.service.d/autologin.conf ]; then echo LOGIN-POLICY-''OK; else echo LOGIN-POLICY-''BAD; fi")
        check("installed system has no live-only passwordless login policy", installed.wait("LOGIN-POLICY-OK", 30, fail="LOGIN-POLICY-BAD"))
    if args.expected_session == "greeter":
        installed.send("if id -nG | grep -qw seat && systemctl -q is-enabled seatd yurei-greeter; then echo GREETER-''OK; else echo GREETER-''BAD; fi")
        check("the user has the seat, and the login screen is on", installed.wait("GREETER-OK", 30, fail="GREETER-BAD"))
    elif args.expected_session == "sddm":
        installed.send("if systemctl -q is-enabled sddm && ! systemctl -q is-enabled yurei-greeter && [ \"$(systemctl get-default)\" = graphical.target ]; then echo SDDM-''ENABLED; else echo SDDM-''BAD; fi")
        check("SDDM is the only enabled display manager", installed.wait("SDDM-ENABLED", 30, fail="SDDM-BAD"))
        if args.desktop_check:
            installed.send("for n in $(seq 1 90); do if pgrep -u sddm -f sddm-greeter >/dev/null; then echo GREETER-''RUNNING; break; fi; sleep 1; done")
            if check("the Wayland SDDM greeter is running", installed.wait("GREETER-RUNNING", 120)):
                time.sleep(4)
                installed.screenshot("installed-sddm.png")
                installed.type_password(password)
                installed.send("for n in $(seq 1 120); do if pgrep -xu \"$(id -u)\" plasmashell >/dev/null && pgrep -xu \"$(id -u)\" kwin_wayland >/dev/null; then echo USER-''PLASMA-OK; break; fi; sleep 1; done")
                check("the installed user logged in through SDDM to Plasma", installed.wait("USER-PLASMA-OK", 150))
                installed.screenshot("installed-plasma.png")
                installed.send("if loginctl list-sessions --no-legend | awk '{print $1}' | xargs -r -n1 loginctl show-session -p Type --value | grep -qx wayland; then echo LOGIND-''WAYLAND; else echo LOGIND-''BAD; fi")
                check("logind registered a Wayland session", installed.wait("LOGIND-WAYLAND", 30, fail="LOGIND-BAD"))
                installed.send("if [ ! -e /etc/systemd/user/pipewire.service.d/90-yurei-live-root.conf ]; then echo AUDIO-POLICY-''OK; else echo AUDIO-POLICY-''BAD; fi")
                check("installed audio keeps normal upstream user policy", installed.wait("AUDIO-POLICY-OK", 30, fail="AUDIO-POLICY-BAD"))
                installed.send("if ! grep -qx '# Yurei live-only wallet policy' /etc/xdg/kwalletrc 2>/dev/null; then echo WALLET-POLICY-''OK; else echo WALLET-POLICY-''BAD; fi")
                check("installed system restores normal wallet policy", installed.wait("WALLET-POLICY-OK", 30, fail="WALLET-POLICY-BAD"))
                check_network_agent(installed, "installed user")
                check_audio(installed, "installed user")
                check_browser(installed, "installed user")
    else:
        installed.send("if [ \"$(systemctl get-default)\" = multi-user.target ]; then echo CONSOLE-''OK; else echo CONSOLE-''BAD; fi")
        check("older seed image retains console boot", installed.wait("CONSOLE-OK", 30, fail="CONSOLE-BAD"))
    request_shutdown(installed, "installed VM", password)
    check("installed VM shut down cleanly", installed.stop())
    if audio_enabled:
        check_recorded_audio(installed, "installed user")

os.remove(disk)
Path(out, "install-result.json").write_text(json.dumps({
    "iso": Path(iso).name, "backend_sha256": hashlib.sha256(args.backend.read_bytes()).hexdigest() if args.backend else None,
    "gui_protocol": args.gui_protocol, "gui_preview_check": args.gui_preview_check,
    "disposable_disk_gib": args.disk_size_gib,
    "expected_session": args.expected_session, "checks": checks,
}, indent=2) + "\n", encoding="utf-8")
sys.exit(0 if results and all(results) else 1)
