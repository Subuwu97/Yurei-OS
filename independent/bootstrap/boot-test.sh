#!/usr/bin/env bash
# The stage 2 milestone: boots the new Yūrei system in QEMU.
#
# Makes a disk image of $YUREI (with the system's files as they are, owned
# by root), and starts Yūrei's own kernel on it with the console on a serial
# port. A small check, added to this test image only, waits until the
# system is up and the login prompt is shown, prints what's running and
# powers off. Fails unless that happens within the time limit.
#
#   sudo YUREI=/path/to/system OUT=/path/to/results ./boot-test.sh
#
# Runs as root on the build host (for the image's owners and for KVM).
set -euo pipefail

yurei=${YUREI:?set YUREI to the new system}
out=${OUT:-$PWD/boot-test}
[[ $EUID -eq 0 ]] || { echo "boot-test.sh: run as root" >&2; exit 1; }
mkdir -p "$out"

kernel=$(compgen -G "$yurei/boot/vmlinuz-*" | head -n1) || true
[[ -n $kernel ]] || { echo "boot-test.sh: no kernel in $yurei/boot" >&2; exit 1; }

# --- the check, for this image only ------------------------------------
mkdir -p "$yurei/usr/local/sbin" "$yurei/etc/systemd/system"
cat > "$yurei/usr/local/sbin/yurei-boot-check" <<'CHECK'
#!/bin/sh
# Boot test only (boot-test.sh): reports on the running system, powers off.
sleep 5  # let the login prompt reach the console first
{
    echo
    echo "YUREI-BOOT-OK"
    . /etc/os-release
    echo "$PRETTY_NAME, kernel $(uname -r)"
    systemctl --version | head -n1
    echo "state: $(systemctl is-system-running)"
    echo "network: $(networkctl list --no-legend 2>/dev/null | tr -s ' ' | tr '\n' ';')"
    echo "failed units:"
    systemctl --failed --no-legend --plain
    echo "YUREI-BOOT-END"
} > /dev/console 2>&1
systemctl poweroff
CHECK
chmod 755 "$yurei/usr/local/sbin/yurei-boot-check"
cat > "$yurei/etc/systemd/system/yurei-boot-check.service" <<'UNIT'
[Unit]
Description=Yūrei boot test
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/yurei-boot-check

[Install]
WantedBy=multi-user.target
UNIT
mkdir -p "$yurei/etc/systemd/system/multi-user.target.wants"
ln -sf ../yurei-boot-check.service "$yurei/etc/systemd/system/multi-user.target.wants/"

# --- the disk image ------------------------------------------------------
image=$out/yurei.img
rm -f "$image"
echo "making the disk image from $yurei"
start=$SECONDS
mke2fs -q -t ext4 -L yurei -d "$yurei" "$image" 10G
echo "  ($((SECONDS - start)) s)"

# --- boot ----------------------------------------------------------------
accel=(-cpu max)
[[ -w /dev/kvm ]] && accel=(-enable-kvm -cpu host)
echo "booting $(basename "$kernel") (${accel[0]})"
start=$SECONDS
timeout 900 qemu-system-x86_64 "${accel[@]}" -m 2048 -smp 2 -nographic -no-reboot \
    -kernel "$kernel" -append "root=/dev/vda rw console=ttyS0" \
    -drive "file=$image,format=raw,if=virtio" -nic user,model=virtio-net-pci \
    < /dev/null | tee "$out/serial.log" || true
echo "  ($((SECONDS - start)) s)"

# --- results -------------------------------------------------------------
fail=0
check() {
    if grep -qa "$2" "$out/serial.log"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
check "Yūrei's kernel started" "Linux version .*-yurei"
check "systemd started" "systemd.*running in system mode"
check "login prompt shown" "yurei login:"
check "the system came up and reported" "YUREI-BOOT-OK"
check "it powered off cleanly" "reboot: Power down"
exit $fail
