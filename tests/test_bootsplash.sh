#!/usr/bin/env bash
# Runs the bootsplash and login-screen helpers against fake system roots
# covering the setups a CachyOS install can have.
# checks are eval'd strings, so expansions are deliberately single-quoted
# shellcheck disable=SC2016,SC2034,SC2329
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bootsplash=$here/pkg/yurei-settings/files/usr/lib/yurei/bootsplash
login_screen=$here/pkg/yurei-settings/files/usr/lib/yurei/login-screen
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export YUREI_DRY_RUN=1

fail=0
check() {
    if eval "$2"; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

new_root() {  # new_root NAME TOOL...: fake root with a Yūrei theme and the given tools
    local root=$tmp/$1; shift
    mkdir -p "$root"/{etc/default,usr/bin,usr/share/plymouth/themes/yurei,etc/kernel}
    local tool
    for tool in "$@"; do touch "$root/usr/bin/$tool"; done
    printf '%s' "$root"
}

splash() { YUREI_ROOT=$1 "$bootsplash" "${@:2}" >/dev/null; }
hook_count() { grep '^HOOKS=' "$1" | tr -s '() ' '\n' | grep -cx "$2"; }

# --- A: mkinitcpio + Limine (CachyOS default) ---------------------------------
A=$(new_root A mkinitcpio limine-update)
printf 'MODULES=()\nHOOKS=(base udev autodetect microcode kms modconf block keyboard keymap consolefont filesystems fsck)\n' > "$A/etc/mkinitcpio.conf"
printf 'ESP_PATH="/boot"\nKERNEL_CMDLINE[default]="nvme_load=yes rw root=UUID=1234"\nKERNEL_CMDLINE[fallback]="rw root=UUID=1234"\n' > "$A/etc/default/limine"
cp "$A/etc/mkinitcpio.conf" "$tmp/A.mkinitcpio"; cp "$A/etc/default/limine" "$tmp/A.limine"
splash "$A" on
check "A: plymouth and text hooks after kms" 'grep -q "^HOOKS=(base udev autodetect microcode kms plymouth yurei-plymouth-text modconf" "$A/etc/mkinitcpio.conf"'
check "A: splash added to the default entry" 'grep -qx "KERNEL_CMDLINE\[default\]=\"nvme_load=yes rw root=UUID=1234 quiet splash\"" "$A/etc/default/limine"'
check "A: fallback entry untouched" 'grep -qx "KERNEL_CMDLINE\[fallback\]=\"rw root=UUID=1234\"" "$A/etc/default/limine"'
check "A: theme selected" 'grep -qx "Theme=yurei" "$A/etc/plymouth/plymouthd.conf"'
check "A: initramfs and Limine regenerated" 'grep -qx "mkinitcpio -P" "$A/commands.log" && grep -qx "limine-update" "$A/commands.log"'
check "A: backups made" '[[ -f $A/etc/mkinitcpio.conf.yurei-bak && -f $A/etc/default/limine.yurei-bak ]]'
status=$(YUREI_ROOT=$A "$bootsplash" status)
check "A: status reports it" 'grep -q "splash.*yes (/etc/default/limine)" <<< "$status"'
splash "$A" on
check "A: running twice changes nothing" '[[ $(grep -o splash "$A/etc/default/limine" | wc -l) -eq 1 && $(hook_count "$A/etc/mkinitcpio.conf" plymouth) -eq 1 && $(hook_count "$A/etc/mkinitcpio.conf" yurei-plymouth-text) -eq 1 ]]'
splash "$A" off
check "A: off restores mkinitcpio.conf" 'cmp -s "$A/etc/mkinitcpio.conf" "$tmp/A.mkinitcpio"'
check "A: off restores Limine options" 'cmp -s "$A/etc/default/limine" "$tmp/A.limine"'
check "A: off clears the theme" '! grep -q "Theme=yurei" "$A/etc/plymouth/plymouthd.conf"'
check "A: state removed" '[[ ! -e $A/var/lib/yurei/bootsplash.state ]]'

# --- B: systemd-based initramfs, encryption, sdboot-manage, quiet already set -
B=$(new_root B mkinitcpio sdboot-manage)
printf 'HOOKS=(base systemd autodetect microcode modconf keyboard sd-vconsole block sd-encrypt filesystems fsck)\n' > "$B/etc/mkinitcpio.conf"
printf 'LINUX_OPTIONS="zswap.enabled=0 quiet"\n' > "$B/etc/sdboot-manage.conf"
splash "$B" on
check "B: plymouth after systemd, before sd-encrypt" 'grep -q "^HOOKS=(base systemd plymouth yurei-plymouth-text autodetect.* sd-encrypt" "$B/etc/mkinitcpio.conf"'
check "B: only splash added" 'grep -qx "LINUX_OPTIONS=\"zswap.enabled=0 quiet splash\"" "$B/etc/sdboot-manage.conf"'
check "B: sdboot-manage regenerated" 'grep -qx "sdboot-manage gen" "$B/commands.log"'
splash "$B" off
check "B: off keeps the user's own quiet" 'grep -qx "LINUX_OPTIONS=\"zswap.enabled=0 quiet\"" "$B/etc/sdboot-manage.conf"'

# --- C: dracut + GRUB ---------------------------------------------------------
C=$(new_root C dracut grub-mkconfig)
printf 'GRUB_TIMEOUT=5\nGRUB_CMDLINE_LINUX_DEFAULT="loglevel=3"\n' > "$C/etc/default/grub"
splash "$C" on
check "C: dracut module enabled" 'grep -q "plymouth" "$C/etc/dracut.conf.d/yurei-plymouth.conf"'
check "C: GRUB options" 'grep -qx "GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet splash\"" "$C/etc/default/grub"'
check "C: dracut and grub-mkconfig run" 'grep -qx "dracut --regenerate-all --force" "$C/commands.log" && grep -qx "grub-mkconfig -o /boot/grub/grub.cfg" "$C/commands.log"'
splash "$C" off
check "C: off removes dracut config and options" '[[ ! -e $C/etc/dracut.conf.d/yurei-plymouth.conf ]] && grep -qx "GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3\"" "$C/etc/default/grub"'

# --- D: Plymouth already set up with another theme -----------------------------
D=$(new_root D mkinitcpio)
printf 'HOOKS=(base udev plymouth autodetect kms block filesystems)\n' > "$D/etc/mkinitcpio.conf"
mkdir -p "$D/etc/plymouth"; printf '[Daemon]\nTheme=cachyos\nShowDelay=0\n' > "$D/etc/plymouth/plymouthd.conf"
printf 'root=UUID=1 rw quiet splash\n' > "$D/etc/kernel/cmdline"
splash "$D" on
check "D: existing hook kept, text hook added after it" '[[ $(hook_count "$D/etc/mkinitcpio.conf" plymouth) -eq 1 ]] && grep -q "udev plymouth yurei-plymouth-text autodetect" "$D/etc/mkinitcpio.conf"'
check "D: other settings kept" 'grep -qx "ShowDelay=0" "$D/etc/plymouth/plymouthd.conf" && grep -qx "Theme=yurei" "$D/etc/plymouth/plymouthd.conf"'
splash "$D" off
check "D: previous theme restored, own hook kept, text hook removed" 'grep -qx "Theme=cachyos" "$D/etc/plymouth/plymouthd.conf" && grep -qx "HOOKS=(base udev plymouth autodetect kms block filesystems)" "$D/etc/mkinitcpio.conf"'
check "D: /etc/kernel/cmdline untouched" 'grep -qx "root=UUID=1 rw quiet splash" "$D/etc/kernel/cmdline"'

# --- E: /etc/kernel/cmdline only (kernel-install / UKI) -------------------------
E=$(new_root E mkinitcpio)
printf 'HOOKS=(base udev kms block filesystems)\n' > "$E/etc/mkinitcpio.conf"
printf 'root=UUID=9 rw\n' > "$E/etc/kernel/cmdline"
splash "$E" on
check "E: words appended to /etc/kernel/cmdline" 'grep -qx "root=UUID=9 rw quiet splash" "$E/etc/kernel/cmdline"'
splash "$E" off
check "E: off restores it" 'grep -qx "root=UUID=9 rw" "$E/etc/kernel/cmdline"'

# --- F: theme package missing ------------------------------------------------
F=$tmp/F; mkdir -p "$F/etc"
check "F: refuses without the theme" '! YUREI_ROOT=$F "$bootsplash" on 2>/dev/null'

# --- the text hook adds the plugin and font the way upstream does --------------
H=$tmp/hook; mkdir -p "$H/bin" "$H/plugins" "$H/fonts"
touch "$H/plugins/label-freetype.so" "$H/plugins/label-pango.so" "$H/fonts/NotoSans.ttf"
printf '#!/bin/sh\necho %s/plugins\n' "$H" > "$H/bin/plymouth"
printf '#!/bin/sh\nprintf %%s %s/fonts/NotoSans.ttf\n' "$H" > "$H/bin/fc-match"
chmod +x "$H/bin/plymouth" "$H/bin/fc-match"
calls=$(PATH="$H/bin:$PATH" bash -c '
    add_binary() { echo "binary $*"; }
    add_file() { echo "file $*"; }
    source "$1"; build' _ "$here/pkg/yurei-settings/files/usr/lib/initcpio/install/yurei-plymouth-text")
check "text hook: adds one text plugin (freetype first)" '[[ $calls == *"binary $H/plugins/label-freetype.so"* && $calls != *label-pango* ]]'
check "text hook: font where label-freetype looks for it" '[[ $calls == *"file $H/fonts/NotoSans.ttf /usr/share/fonts/Plymouth.ttf"* ]]'

# --- login screen --------------------------------------------------------------
L=$tmp/L
mkdir -p "$L"/{usr/bin,usr/share/sddm/themes/yurei,etc/systemd/system,etc/plasmalogin.conf.d,usr/lib/systemd/system}
touch "$L/usr/bin/sddm"; chmod +x "$L/usr/bin/sddm"
ln -s /usr/lib/systemd/system/plasmalogin.service "$L/etc/systemd/system/display-manager.service"
printf '[Autologin]\nUser=ana\nSession=yurei-steam.desktop\nRelogin=true\n' > "$L/etc/plasmalogin.conf.d/zz-yurei-session.conf"
YUREI_ROOT=$L "$login_screen" yurei >/dev/null
check "login: SDDM enabled" 'grep -qx "systemctl enable --force sddm.service" "$L/commands.log"'
check "login: previous manager remembered" 'grep -qx "plasmalogin.service" "$L/var/lib/yurei/login-screen.previous"'
check "login: theme selected" 'grep -qx "Current=yurei" "$L/etc/sddm.conf.d/10-yurei-theme.conf"'
check "login: game-mode autologin carried over" 'grep -q "yurei-steam" "$L/etc/sddm.conf.d/zz-yurei-session.conf"'
YUREI_ROOT=$L "$login_screen" plasma >/dev/null
check "login: rollback re-enables plasma-login-manager" 'grep -qx "systemctl enable --force plasmalogin.service" "$L/commands.log"'
check "login: rollback removes the theme setting" '[[ ! -e $L/etc/sddm.conf.d/10-yurei-theme.conf && ! -e $L/var/lib/yurei/login-screen.previous ]]'
M=$tmp/M; mkdir -p "$M/usr/bin"
check "login: refuses without SDDM" '! YUREI_ROOT=$M "$login_screen" yurei 2>/dev/null'
exit $fail
