#!/bin/bash
# The live ISO's contents, made inside the Yūrei chroot (started by
# `chroot.sh iso-inside.sh`) after stage 2c, from the [yurei] repository in
# /srv/yurei/repo only:
#
#   /srv/yurei/live       the live system, installed by pacman
#   /srv/yurei/initramfs  the small system that starts it: finds the ISO,
#                         mounts its squashfs under a RAM overlay, switches
#   /srv/yurei/esp        the kernel, initramfs and systemd-boot for UEFI
#
# iso.sh then packs them into the ISO on the build machine.
set -euo pipefail

# shellcheck source=independent/bootstrap/inside-lib.sh
source /bootstrap/inside-lib.sh

srv=/srv/yurei
repo=$srv/repo
live=$srv/live
initramfs=$srv/initramfs
esp=$srv/esp

live_system() {
    msg "The live system, installed from [yurei] by pacman"
    local gnupg=$srv/live-gnupg fpr all
    rm -rf "$live" "$gnupg"
    mkdir -p "$live/var/lib/pacman" "$gnupg"
    cat > "$srv/live-pacman.conf" <<CONF
[options]
Architecture = auto
SigLevel = Required DatabaseRequired
CacheDir = $srv/live-cache

[yurei]
Server = file://$repo
CONF
    fpr=$(gpg --batch --with-colons --show-keys "$repo/yurei-build.asc" | awk -F: '/^fpr/ {print $10; exit}')
    pacman-key --config "$srv/live-pacman.conf" --gpgdir "$gnupg" --init
    pacman-key --config "$srv/live-pacman.conf" --gpgdir "$gnupg" --add "$repo/yurei-build.asc"
    pacman-key --config "$srv/live-pacman.conf" --gpgdir "$gnupg" --lsign-key "$fpr"
    local p=(pacman --config "$srv/live-pacman.conf" --root "$live" --dbpath "$live/var/lib/pacman"
             --gpgdir "$gnupg" --noconfirm)
    "${p[@]}" -Sy
    mapfile -t all < <("${p[@]}" -Slq yurei)
    "${p[@]}" -S "${all[@]}"
    gpgconf --homedir "$gnupg" --kill all
    rm -rf "$gnupg" "$srv/live-cache" "$srv/live-pacman.conf"
    echo "$("${p[@]}" -Qq | wc -l) packages"
}

live_settings() {
    msg "Live settings"
    echo yurei-live > "$live/etc/hostname"
    # root without a password, logged in on the first screen
    sed -i 's/^root:[^:]*:/root::/' "$live/etc/shadow"
    install -d "$live/etc/systemd/system/getty@tty1.service.d"
    cat > "$live/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'UNIT'
[Service]
ExecStart=
ExecStart=-/usr/sbin/agetty --autologin root --noclear %I $TERM
UNIT
    cat > "$live/etc/issue" <<'ISSUE'

  Yūrei Linux (independent preview), live

ISSUE
    cat > "$live/etc/motd" <<'MOTD'

  Welcome to Yūrei, built entirely from source by Yūrei itself.

  This is a live system: changes are kept in memory until you shut down.
  pacman -Q        lists what's installed (all from Yūrei's own repository)
  poweroff         shuts down

MOTD
    rm -rf "$live"/var/cache/pacman/pkg/*
}

# The initramfs: just enough of the live system's programs, and their
# libraries, to find and start it.
initramfs_tree() {
    msg "The initramfs"
    rm -rf "$initramfs"
    mkdir -p "$initramfs"/{usr/bin,usr/sbin,usr/lib,dev,proc,sys,run,newroot}
    ln -s usr/bin "$initramfs/bin"
    ln -s usr/sbin "$initramfs/sbin"
    ln -s usr/lib "$initramfs/lib"
    ln -s usr/lib "$initramfs/lib64"
    local prog lib
    for prog in /usr/bin/{bash,mount,umount,mkdir,sleep,cat} /usr/sbin/{blkid,losetup,switch_root} /usr/bin/setsid; do
        install -D "$live$prog" "$initramfs$prog"
        while read -r lib; do
            [[ -e $initramfs$lib ]] || install -D "$live$lib" "$initramfs$lib"
        done < <(chroot "$live" ldd "$prog" | grep -o '/[^ ]*' | sort -u)
    done
    cat > "$initramfs/init" <<'INIT'
#!/usr/bin/bash
# Starts the Yūrei live system: finds the live medium, mounts its squashfs
# read-only under a RAM overlay, and hands over to systemd.
#
# The medium is found in one of three ways, tried in turn:
#   1. by its label, YUREI_LIVE (a DVD, or a USB stick written with Etcher,
#      Rufus in DD mode or dd);
#   2. the same, by probing each disk and partition directly, in case
#      blkid's quick lookup misses it;
#   3. as an ISO file on a USB stick's partition (Ventoy, or the ISO just
#      copied onto a stick): any yurei*.iso at the top or one folder down.
PATH=/usr/bin:/usr/sbin
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
# /run is moved into the live system with everything mounted under it
mount -t tmpfs -o mode=0755,nosuid,nodev run /run
# through the kernel's log, so every console shows it (the screen and, in
# the tests, the serial port); plain ASCII, which every console shows right
say() { echo "Yurei: $*" > /dev/kmsg 2>/dev/null || echo "Yurei: $*"; }
mkdir -p /run/live/medium /run/live/host /run/live/rootfs /run/live/rw

live_medium() {  # DEVICE-OR-FILE: mounts it as the medium if it is one
    mount -o ro "$1" /run/live/medium 2>/dev/null || return 1
    [[ -f /run/live/medium/yurei/rootfs.sfs ]] && return 0
    umount /run/live/medium
    return 1
}

by_label() {
    local dev
    dev=$(blkid -L YUREI_LIVE 2>/dev/null) && [[ -n $dev ]] && live_medium "$dev" && found=$dev
}

by_probe() {
    local b dev
    for b in /sys/class/block/*; do
        dev=/dev/${b##*/}
        [[ $(blkid -p -o value -s LABEL "$dev" 2>/dev/null) == YUREI_LIVE ]] || continue
        live_medium "$dev" && { found=$dev; return 0; }
    done
    return 1
}

by_file() {
    local b dev type iso
    for b in /sys/class/block/*; do
        dev=/dev/${b##*/}
        type=$(blkid -p -o value -s TYPE "$dev" 2>/dev/null)
        case $type in vfat|exfat|ntfs|ext4|ext3|ext2|iso9660) ;; *) continue ;; esac
        mount -o ro "$dev" /run/live/host 2>/dev/null || continue
        shopt -s nullglob nocaseglob
        for iso in /run/live/host/yurei*.iso /run/live/host/*/yurei*.iso; do
            if live_medium "$iso"; then
                shopt -u nullglob nocaseglob
                found="$iso on $dev"
                return 0
            fi
        done
        shopt -u nullglob nocaseglob
        umount /run/live/host
    done
    return 1
}

say "looking for the live medium..."
found=
for i in {1..45}; do
    by_label || by_probe || { (( i >= 3 )) && by_file; } && break
    sleep 1
done
if [[ -z $found ]]; then
    say "the live medium wasn't found. What the system sees:"
    {
        echo
        echo "Yurei: the live medium wasn't found."
        echo "Disks and partitions seen (/proc/partitions):"
        cat /proc/partitions
        echo "What's on them (blkid):"
        blkid
        echo
        echo "A shell, to look around (type exit to try again):"
    } > /dev/tty1 2>&1
    while :; do
        setsid -c -w bash -i 0<>/dev/tty1 1>&0 2>&1
        found=
        by_label || by_probe || by_file && break
        echo "Still not found. Another shell:" > /dev/tty1
    done
fi
say "found it on $found, starting"
mount -o loop,ro /run/live/medium/yurei/rootfs.sfs /run/live/rootfs
mount -t tmpfs -o mode=0755 tmpfs /run/live/rw
mkdir -p /run/live/rw/upper /run/live/rw/work
mount -t overlay overlay \
    -o lowerdir=/run/live/rootfs,upperdir=/run/live/rw/upper,workdir=/run/live/rw/work /newroot
exec switch_root /newroot /usr/lib/systemd/systemd
INIT
    chmod 755 "$initramfs/init"
    du -sh "$initramfs"
}

boot_files() {
    msg "UEFI boot files (systemd-boot)"
    rm -rf "$esp"
    install -d "$esp/EFI/BOOT" "$esp/loader/entries" "$esp/yurei"
    install -m644 "$live/usr/lib/systemd/boot/efi/systemd-bootx64.efi" "$esp/EFI/BOOT/BOOTX64.EFI"
    install -m644 "$live/boot/vmlinuz-yurei" "$esp/yurei/vmlinuz"
    printf 'default yurei.conf\ntimeout 3\n' > "$esp/loader/loader.conf"
    # the screen last, so it's the main console; the serial port is for tests
    cat > "$esp/loader/entries/yurei.conf" <<ENTRY
title   Yūrei Linux (live)
linux   /yurei/vmlinuz
initrd  /yurei/initramfs.img
options console=ttyS0,115200 console=tty0 systemd.tty.term.ttyS0=dumb
ENTRY
    ls -lR "$esp"
}

STEPS=(live_system live_settings initramfs_tree boot_files)
run_steps "$@"
