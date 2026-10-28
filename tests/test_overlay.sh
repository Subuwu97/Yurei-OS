#!/usr/bin/env bash
# Applies the overlay to a real checkout of the pinned CachyOS-Live-ISO and
# checks every change landed. Usage: tests/test_overlay.sh [UPSTREAM_CHECKOUT]
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

source "$here/upstream.conf"
if [[ -n ${1:-} ]]; then
    cp -a "$1" "$tmp/upstream"
else
    git clone --quiet "$UPSTREAM_URL" "$tmp/upstream"
fi
git -C "$tmp/upstream" checkout --quiet --force --detach "$UPSTREAM_REF"

export WORK_DIR=$tmp
source "$here/build.sh"
mkdir -p "$work/packages"
touch "$work/packages/yurei-settings-0.2.0-1-any.pkg.tar.zst" "$work/packages/yurei-gaming-0.2.0-1-any.pkg.tar.zst"

apply_overlay

iso=$tmp/upstream/archiso
fail=0
expect() {
    if grep -q -- "$2" "$1"; then
        printf 'ok   %s\n' "$3"
    else
        printf 'FAIL %s\n' "$3"
        fail=1
    fi
}
expect "$iso/packages_desktop.x86_64" '^yurei-settings$' "Yūrei settings added to package list"
if grep -qx yurei-gaming "$iso/packages_desktop.x86_64"; then echo "FAIL gaming stack kept off the live ISO"; fail=1; else echo "ok   gaming stack kept off the live ISO"; fi
expect "$iso/packages_desktop.x86_64" '^linux-cachyos$' "CachyOS kernel still in package list"
expect "$iso/pacman.conf" '^\[yurei\]$' "local repository configured"
expect "$iso/profiledef.sh" 'iso_application="Yūrei' "ISO metadata rebranded"
expect "$iso/profiledef.sh" 'yurei-install-target"\]="0:0:755"' "installer helper is executable"
expect "$iso/grub/grub.cfg" 'menuentry "Yurei"' "boot menu rebranded"
expect "$iso/airootfs/etc/os-release" 'NAME="Yūrei"' "live system rebranded"
expect "$iso/airootfs/usr/local/bin/calamares-online.sh" 'yurei-calamares-patch' "installer hook added"
if [[ -f $iso/airootfs/opt/yurei/packages/yurei-gaming-0.2.0-1-any.pkg.tar.zst ]]; then
    echo "ok   packages shipped on the ISO"
else
    echo "FAIL packages shipped on the ISO"; fail=1
fi
if cmp -s "$here/overlay/boot/splash.png" "$iso/grub/splash.png"; then
    echo "ok   boot splash replaced"
else
    echo "FAIL boot splash replaced"; fail=1
fi
if grep -q 'CachyOS' "$iso/grub/grub.cfg"; then echo "FAIL leftover CachyOS in grub.cfg"; fail=1; fi

# the boot animation on the live system
expect "$iso/packages_desktop.x86_64" '^yurei-plymouth-theme$' "boot animation on the live ISO"
expect "$iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf" '^HOOKS=(base udev plymouth yurei-plymouth-text microcode ' \
    "boot animation in the live initramfs"
expect "$iso/airootfs/etc/pacman.d/hooks/85-yurei-live-plymouth.hook" 'remove from airootfs' "theme hook cleaned up after the build"
for f in "$iso/grub/grub.cfg" "$iso/syslinux/archiso_sys-linux.cfg" "$iso"/efiboot/loader/entries/0[12]-*.conf; do
    expect "$f" 'pcspkr quiet splash ' "boot animation on: ${f#"$iso"/}"
done
if grep -h 'nomodeset' "$iso"/grub/*.cfg "$iso"/syslinux/*.cfg "$iso"/efiboot/loader/entries/*.conf | grep -q splash; then
    echo "FAIL nomodeset fallback should stay verbose"; fail=1
else
    echo "ok   nomodeset fallback stays verbose"
fi

# the installer's branding and the live desktop's install launcher
expect "$iso/airootfs/usr/share/calamares/branding/yurei/branding.desc" '^componentName:  yurei$' "installer branding shipped"
expect "$iso/airootfs/usr/share/applications/yurei-install.desktop" '^Exec=konsole .* -e /usr/local/bin/yurei-install$' \
    "Install Yūrei launcher opens a window showing the installer starting"
expect "$iso/airootfs/usr/local/bin/yurei-install" 'calamares-online.sh' "it starts CachyOS's installer script"
expect "$iso/profiledef.sh" 'yurei-install"\]="0:0:755"' "Install Yūrei script is executable"

# profiledef.sh must still load the way mkarchiso loads it
if (declare -A file_permissions=()
    # shellcheck disable=SC1091
    source "$iso/profiledef.sh"
    [[ ${file_permissions["/usr/local/bin/yurei-calamares-patch"]} == "0:0:755" &&
       ${file_permissions["/etc/shadow"]} == "0:0:400" ]]); then
    echo "ok   profiledef.sh still loads"
else
    echo "FAIL profiledef.sh"; fail=1
fi
exit $fail
