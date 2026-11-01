# Independent graphical installer

`yurei-install-gui` is a Qt Widgets front end for the independent
`/usr/bin/yurei-install` backend. It reuses the approved shrine artwork from
the existing Calamares branding; it does not launch CachyOS or Calamares.

Screens: welcome, disk selection, accounts, explicit erase review, live
installation output and result. The current backend supports whole-disk erase,
UEFI, a 1 GiB EFI partition, ext4 and systemd-boot. It does not offer dual boot,
manual partitioning, encryption, app selection or a Plasma/SDDM migration yet.

## Preview without touching disks

```sh
cmake -S independent/packages/yurei-install-gui -B work/installer-gui -G Ninja -DBUILD_TESTING=ON
cmake --build work/installer-gui
ctest --test-dir work/installer-gui --output-on-failure
work/installer-gui/yurei-install-gui --preview
```

Preview mode uses a fictitious disk and never runs disk inventory or the install
backend. `--preview --page 3 --screenshot preview.png` saves a review-screen
preview and exits. CI compiles the real C++ GUI, tests its request/disk model,
and renders all six screens; these previews are not a completed installation.

## Live system execution

The desktop entry is visible only while the live rootfs is mounted. Without
`--preview`, installation is enabled only in the UEFI live system. Mounted and
read-only disks, unknown mount states, and targets below 16 GiB are excluded.
The backend also checks actual image size, target size/device number, live
medium protection and mounted filesystems immediately before disk writes.
Only one backend installation may hold the install lock at a time.

Starting installation requires account validation, an erase acknowledgement,
and typing `ERASE /dev/DEVICE` for the selected disk. The unprivileged GUI uses
pkexec with the internal terminal agent disabled; a desktop authentication
agent must be available. A live session already running as root calls the
backend directly. Passwords use standard input, never process arguments or
new password environment variables. Installation output is displayed with the
entered passwords redacted. Closing is blocked during a running installation.

The disk's size and kernel device number are rechecked, but are not a unique
physical identity. Do not unplug or swap target disks during installation.

## Validation before release

The recipe adds the GUI after Qt in ORDER. The real backend still installs the
current live system. It enables SDDM when present, otherwise the temporary
greeter when present, otherwise console boot. It does not
invent a Plasma installation before those packages are available.

Before shipping, test an actual end-to-end install in QEMU with UEFI firmware
and disposable disks, including authentication cancellation, capacity errors,
USB/live-medium exclusion, account creation, password login, reboot and boot
without the live ISO. Source/model tests and UI screenshots do not replace
that test. No real-disk installation should be represented as verified until
the live-system VM test passes.

The dedicated `Independent installer VM test` workflow uses the last published
independent ISO (`independent-2026.10.31-85`), verified against a pinned SHA-256.
It injects the reviewed backend into the live VM's RAM, verifies those bytes,
uses the GUI's stdin-password/device-binding protocol, installs onto a new
32 GiB image, then boots that disk without the ISO and checks user login,
root/EFI mounts and sudo. The seed predates Qt and the greeter, so this validates
the backend handoff and installed console system, not the graphical application
inside the eventual Qt-enabled image or its desktop authentication dialog.

The bootstrap workflow also builds `codex/installer-gui` on a GitHub-hosted
runner. That branch must render all six previews with the actual live image's
GUI binary and Qt libraries before its stdin-protocol installation/reboot test.
This uses Qt's offscreen platform: it checks runtime linkage and rendering,
not compositor integration, mouse interaction or authentication cancellation.
After the boot tests pass, `installer-test-iso` retains the ISO and checksum
for three days as an Actions artifact. Branch builds never publish a release.
