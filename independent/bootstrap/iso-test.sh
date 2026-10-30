#!/usr/bin/env bash
# Boots the live ISO in QEMU on UEFI firmware (OVMF), as a PC would from a
# USB stick or DVD: systemd-boot, Yūrei's kernel, the initramfs finding the
# ISO, and the live system up to its login prompt.
#
#   sudo ISO=/path/to/yurei.iso OUT=/path/to/results ./iso-test.sh
set -euo pipefail

iso=${ISO:?set ISO to the image}
out=${OUT:-$PWD/iso-test}
mkdir -p "$out"
log=$out/iso-serial.log

firmware=
for f in /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
    [[ -f $f ]] && { firmware=$f; break; }
done
[[ -n $firmware ]] || { echo "iso-test.sh: no OVMF firmware (apt install ovmf)" >&2; exit 1; }

accel=(-cpu max)
[[ -w /dev/kvm ]] && accel=(-enable-kvm -cpu host)
: > "$log"
qemu-system-x86_64 "${accel[@]}" -m 3072 -smp 2 -bios "$firmware" \
    -drive "file=$iso,media=cdrom,readonly=on" -boot d \
    -nic user,model=virtio-net-pci -display none -serial "file:$log" -no-reboot &
qemu=$!
start=$SECONDS
# up to 5 minutes for the login prompt
until grep -qa "yurei-live login:" "$log" || (( SECONDS - start > 300 )) || ! kill -0 $qemu 2>/dev/null; do
    sleep 2
done
sleep 3
kill $qemu 2>/dev/null || true
wait $qemu 2>/dev/null || true
echo "  ($((SECONDS - start)) s)"
cat -v "$log" | tail -n 60

fail=0
check() {
    if grep -qa "$2" "$log"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
check "Yūrei's kernel started from systemd-boot" "Linux version .*-yurei"
check "the initramfs found the ISO" "Yūrei: found it on .*, starting"
check "systemd started" "systemd.*running in system mode"
check "the live system reached its login prompt" "yurei-live login:"
exit $fail
