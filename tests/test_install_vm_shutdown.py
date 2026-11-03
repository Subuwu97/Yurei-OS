"""Shutdown must drain the VM console so QEMU can finalize audio output."""
import ast
import os
from pathlib import Path
import subprocess
import sys
import time
import wave


SOURCE = Path(__file__).resolve().parents[1] / "independent/bootstrap/install-test.py"


def machine_class():
    # Load only the class; the script's top level starts destructive test VMs.
    parsed = ast.parse(SOURCE.read_text(encoding="utf-8"))
    definition = next(node for node in parsed.body if isinstance(node, ast.ClassDef) and node.name == "Machine")
    namespace = {"os": os, "subprocess": subprocess, "time": time}
    exec(compile(ast.Module(body=[definition], type_ignores=[]), str(SOURCE), "exec"), namespace)
    return namespace["Machine"]


def child_machine(tmp_path, program):
    cls = machine_class()
    machine = cls.__new__(cls)
    machine.log = (tmp_path / "serial.log").open("wb")
    machine.qemu = subprocess.Popen([sys.executable, "-c", program], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    os.set_blocking(machine.qemu.stdout.fileno(), False)
    return machine


def test_shutdown_drains_console_before_audio_finalization(tmp_path):
    recording = tmp_path / "sound.wav"
    # More than a pipe buffer: waiting without draining blocks the child before
    # it can write/close the recording, just as with QEMU's shutdown messages.
    program = "import sys,wave;sys.stdout.buffer.write(b'x'*262144);sys.stdout.flush();"
    program += "w=wave.open(" + repr(str(recording)) + ",'wb');w.setparams((1,2,8000,0,'NONE','not compressed'));w.writeframes(b'\\x00\\x10'*8000);w.close()"
    machine = child_machine(tmp_path, program)
    assert machine.stop(timeout=10)
    assert (tmp_path / "serial.log").stat().st_size == 262144
    with wave.open(str(recording), "rb") as audio:
        assert audio.getnframes() == 8000


def test_forced_shutdown_is_reported_as_failure(tmp_path):
    machine = child_machine(tmp_path, "import time;time.sleep(60)")
    assert not machine.stop(timeout=0.05)
    assert machine.qemu.poll() is not None


def test_shutdown_keeps_serial_input_open_until_guest_exits(tmp_path):
    # Closing stdin immediately after sending a command can make a stdio-backed
    # emulator discard input. Require the pipe to remain open until child exit.
    program = "import sys,time,os;assert sys.stdin.readline().strip() == 'poweroff';time.sleep(0.1);os.set_blocking(sys.stdin.fileno(),False)\n"
    program += "try:\n data=os.read(sys.stdin.fileno(),1)\nexcept BlockingIOError:\n pass\nelse:\n raise AssertionError('serial input was closed before guest exit: %r' % data)"
    machine = child_machine(tmp_path, program)
    machine.qemu.stdin.write(b'poweroff\n')
    machine.qemu.stdin.flush()
    assert machine.stop(timeout=10)
