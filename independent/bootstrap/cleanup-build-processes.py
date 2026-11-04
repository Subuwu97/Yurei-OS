#!/usr/bin/env python3
"""Stop abandoned build processes without matching host accounts by UID alone."""
import os
from pathlib import Path
import select
import signal
import sys


def belongs_to_build(process, uid, build_root):
    try:
        root = (process / "root").stat()
        if (root.st_dev, root.st_ino) != (build_root.st_dev, build_root.st_ino):
            return False
        for line in (process / "status").read_text().splitlines():
            if line.startswith("Uid:"):
                return [int(value) for value in line.split()[1:]] == [uid] * 4
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return False
    return False


def main():
    import pwd

    uid = pwd.getpwnam(sys.argv[1]).pw_uid
    if uid == 0:
        raise SystemExit("Refusing to clean processes for root")
    build_root = Path("/").stat()
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal() or not belongs_to_build(process, uid, build_root):
            continue
        try:
            # Pin process identity before signalling, then recheck the boundary.
            # A reused numeric PID must never target an unrelated host process.
            fd = os.pidfd_open(int(process.name))
        except ProcessLookupError:
            continue
        try:
            if not belongs_to_build(process, uid, build_root):
                continue
            print("Stopping abandoned build process", process.name, flush=True)
            signal.pidfd_send_signal(fd, signal.SIGTERM)
            if not select.select([fd], [], [], 2)[0]:
                signal.pidfd_send_signal(fd, signal.SIGKILL)
                if not select.select([fd], [], [], 2)[0]:
                    raise RuntimeError("Build process did not exit: " + process.name)
        except ProcessLookupError:
            pass
        finally:
            os.close(fd)


if __name__ == "__main__":
    main()
