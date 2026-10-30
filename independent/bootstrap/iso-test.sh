#!/usr/bin/env bash
# Boots the live ISO in QEMU on UEFI firmware (OVMF), the ways a PC starts
# it, each up to the live system's login prompt:
#
#   dvd    the ISO as a DVD
#   usb    the ISO written to a USB stick (Etcher, Rufus in DD mode, dd)
#   file   the ISO as a file on a FAT32 USB stick, as Ventoy keeps it; the
#          kernel and initramfs are started directly here (Ventoy's own
#          boot menu does that on a PC), so it tests the initramfs finding
#          the ISO file. Needs ESP, the ISO's boot files (iso-inside.sh's
#          /srv/yurei/esp); skipped without it.
#
#   sudo ISO=/path/to/yurei.iso [ESP=/path/to/esp] OUT=/path/to/results ./iso-test.sh
set -euo pipefail

iso=${ISO:?set ISO to the image}
esp=${ESP:-}
out=${OUT:-$PWD/iso-test}
mkdir -p "$out"

firmware=
for f in /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
    [[ -f $f ]] && { firmware=$f; break; }
done
[[ -n $firmware ]] || { echo "iso-test.sh: no OVMF firmware (apt install ovmf)" >&2; exit 1; }

accel=(-cpu max)
[[ -w /dev/kvm ]] && accel=(-enable-kvm -cpu host)
fail=0

# boot NAME QEMU-ARGS...: boots, waits for the login prompt, checks the log
boot() {
    local name=$1 log=$out/iso-$1.log qemu start
    shift
    echo "== $name"
    : > "$log"
    qemu-system-x86_64 "${accel[@]}" -m 3072 -smp 2 -bios "$firmware" "$@" \
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
    cat -v "$log" | tail -n 40
    check() {
        if grep -qa "$2" "$log"; then echo "ok   $name: $1"; else echo "FAIL $name: $1"; fail=1; fi
    }
    [[ $name == file ]] || check "Yūrei's kernel started from systemd-boot" "Linux version .*-yurei"
    check "the initramfs found the ISO" "Yurei: found it on .*, starting"
    check "systemd started" "systemd.*running in system mode"
    check "the live system reached its login prompt" "yurei-live login:"
}

boot dvd -drive "file=$iso,media=cdrom,readonly=on" -boot d

boot usb -device qemu-xhci \
    -drive "if=none,id=stick,format=raw,file=$iso,snapshot=on" \
    -device usb-storage,drive=stick,removable=on

if [[ -n $esp ]]; then
    stick=$out/fat-stick.img
    rm -f "$stick"
    truncate -s $(( $(stat -c %s "$iso") / 1048576 + 64 ))M "$stick"
    mkfs.fat -F 32 -n VENTOY "$stick" > /dev/null
    mmd -i "$stick" ::/isos
    mcopy -i "$stick" "$iso" ::/isos/
    boot file -kernel "$esp/yurei/vmlinuz" -initrd "$esp/yurei/initramfs.img" \
        -append "console=ttyS0,115200 systemd.tty.term.ttyS0=dumb" \
        -device qemu-xhci \
        -drive "if=none,id=stick,format=raw,file=$stick" \
        -device usb-storage,drive=stick,removable=on
    rm -f "$stick"
else
    echo "== file: skipped (no ESP)"
fi
exit $fail
