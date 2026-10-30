#!/usr/bin/env bash
# Packs the live system that iso-inside.sh made (in $YUREI/srv/yurei) into
# a UEFI ISO, bootable from a USB stick or a DVD:
#
#   yurei/rootfs.sfs     the live system, as squashfs (zstd)
#   an EFI partition     systemd-boot, the kernel and the initramfs
#
# Runs as root on the build machine. Its packing tools (mksquashfs, cpio,
# mkfs.fat, mtools, xorriso) only put Yūrei's files together; nothing of
# the build machine goes into the ISO.
#
#   sudo YUREI=/path/to/system OUT=/path/to/output ./iso.sh
set -euo pipefail

yurei=${YUREI:?set YUREI to the build system}
out=${OUT:?set OUT to the output directory}
srv=$yurei/srv/yurei
name=${ISO_NAME:-yurei-independent-$(date +%Y.%m.%d)-x86_64.iso}
work=$out/work
[[ -d $srv/live && -d $srv/initramfs && -d $srv/esp ]] || { echo "run iso-inside.sh first" >&2; exit 1; }

rm -rf "$work" && mkdir -p "$work/iso/yurei" "$out"

echo "== squashfs of the live system"
mksquashfs "$srv/live" "$work/iso/yurei/rootfs.sfs" -comp zstd -Xcompression-level 15 \
    -noappend -quiet -e boot
du -h "$work/iso/yurei/rootfs.sfs"

echo "== initramfs"
(cd "$srv/initramfs" && find . -print0 | cpio --null -o -H newc --quiet | gzip -9) \
    > "$srv/esp/yurei/initramfs.img"
du -h "$srv/esp/yurei/initramfs.img"

echo "== EFI partition"
esp_kb=$(( $(du -sk "$srv/esp" | cut -f1) + 8192 ))
truncate -s "${esp_kb}K" "$work/efiboot.img"
mkfs.fat -n YUREI_ESP "$work/efiboot.img" > /dev/null
(cd "$srv/esp" && mcopy -s -i "$work/efiboot.img" ./* ::/)
mdir -i "$work/efiboot.img" -/ :: || true

echo "== ISO"
xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -joliet -joliet-long -rational-rock \
    -volid YUREI_LIVE -appid "Yūrei Linux live" -publisher "Yūrei Linux project" \
    -partition_offset 16 \
    -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "$work/efiboot.img" \
    -appended_part_as_gpt \
    -eltorito-alt-boot -e --interval:appended_partition_2:all:: -no-emul-boot \
    -output "$out/$name" "$work/iso"
(cd "$out" && sha256sum "$name" > "$name.sha256")
rm -rf "$work"
ls -lh "$out"
