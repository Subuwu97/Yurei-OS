#!/usr/bin/env bash
# Runs yurei-install-target against a fake target system, with arch-chroot
# replaced by a stub that records what would run inside it.
# checks are eval'd strings, so expansions are deliberately single-quoted
# shellcheck disable=SC2016,SC2034
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script=$here/overlay/airootfs/usr/local/bin/yurei-install-target
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/pkgs" "$tmp/root/etc" "$tmp/root/tmp"
cat > "$tmp/bin/arch-chroot" <<STUB
#!/bin/sh
shift
echo "\$*" >> "$tmp/chroot-calls"
# packages "installed" in the fake target
[ "\$*" = "pacman -Qq" ] && cat "$tmp/installed" 2>/dev/null
exit 0
STUB
# graphics hardware as \`lspci -n\` reports it
printf '00:02.0 0300: 8086:9bc8 (rev 05)\n01:00.0 0300: 1002:73df (rev c1)\n00:1f.3 0403: 8086:a348\n' > "$tmp/lspci-amd-intel"
printf '01:00.0 0300: 10de:2684 (rev a1)\n00:1f.3 0403: 8086:a348\n' > "$tmp/lspci-nvidia"
printf '00:02.0 0300: 1234:1111 (rev 02)\n' > "$tmp/lspci-vm"
printf '#!/bin/sh\ncat "$YUREI_LSPCI_FIXTURE"\n' > "$tmp/bin/fake-lspci"
chmod +x "$tmp/bin/fake-lspci"
export YUREI_LSPCI=$tmp/bin/fake-lspci YUREI_LSPCI_FIXTURE=$tmp/lspci-vm
chmod +x "$tmp/bin/arch-chroot"
touch "$tmp/pkgs/yurei-settings-0.1.0-1-any.pkg.tar.zst" "$tmp/pkgs/yurei-gaming-0.1.0-1-any.pkg.tar.zst"
# helpers the packages would install
mkdir -p "$tmp/root/usr/lib/yurei"
for helper in login-screen bootsplash theme-defaults; do
    printf '#!/bin/sh\n' > "$tmp/root/usr/lib/yurei/$helper"
    chmod +x "$tmp/root/usr/lib/yurei/$helper"
done
printf 'root:x:0:0::/root:/bin/bash\nana:x:1000:1000::/home/ana:/bin/bash\nnobody:x:65534:65534::/:/usr/bin/nologin\n' > "$tmp/root/etc/passwd"
printf '[options]\n\n[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n' > "$tmp/root/etc/pacman.conf"
# what CachyOS's installer leaves behind: Hello's autostart, and a Limine menu
mkdir -p "$tmp/root/home/ana/.config/autostart" "$tmp/root/boot" "$tmp/root/usr/share/yurei"
touch "$tmp/root/home/ana/.config/autostart/cachyos-hello.desktop" "$tmp/root/home/ana/.config/autostart/other.desktop" \
      "$tmp/root/home/ana/.config/kdeglobals"
printf 'timeout: 5\nwallpaper: boot():/limine-splash.png\n\ncomment: machine-id=abc\n/+CachyOS\n  //linux-cachyos\n' > "$tmp/root/boot/limine.conf"
echo cachyos > "$tmp/root/boot/limine-splash.png"
echo yurei > "$tmp/root/usr/share/yurei/boot-splash.png"

# throwaway signing key
export GNUPGHOME=$tmp/gnupg
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-gen-key "Test <test@yurei.invalid>" ed25519 sign never 2>/dev/null
gpg --batch --armor --export > "$tmp/yurei.asc"
fpr=$(gpg --batch --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr/ {print $10; exit}')

fail=0
check() {
    if eval "$2"; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

PATH="$tmp/bin:$PATH" YUREI_PKG_DIR="$tmp/pkgs" YUREI_SIGNING_KEY_FILE="$tmp/nokey" "$script" "$tmp/root"
check "login screen switched to Yūrei" 'grep -qx "/usr/lib/yurei/login-screen yurei" "$tmp/chroot-calls"'
check "boot animation enabled" 'grep -qx "/usr/lib/yurei/bootsplash on" "$tmp/chroot-calls"'
drivers() {  # drivers FIXTURE [INSTALLED]: the driver install command for that hardware
    : > "$tmp/chroot-calls"
    printf '%s' "${2:-}" > "$tmp/installed"
    PATH="$tmp/bin:$PATH" YUREI_LSPCI_FIXTURE="$tmp/lspci-$1" YUREI_PKG_DIR="$tmp/pkgs" \
        YUREI_SIGNING_KEY_FILE="$tmp/nokey" "$script" "$tmp/root" >/dev/null
    grep '^pacman -S ' "$tmp/chroot-calls" || true
}
d=$(drivers amd-intel)
check "AMD + Intel (hybrid): both Vulkan drivers, 32 and 64-bit" '[[ $d == *"vulkan-radeon lib32-vulkan-radeon"* && $d == *"vulkan-intel lib32-vulkan-intel"* ]]'
check "a sound card (also Intel) doesn't count as graphics" '[[ $(drivers nvidia) != *vulkan-intel* ]]'
d=$(drivers nvidia "nvidia-utils")
check "NVIDIA: 32-bit driver matching CachyOS's" '[[ $d == "pacman -S --noconfirm --needed lib32-nvidia-utils" ]]'
d=$(drivers nvidia "nvidia-470xx-utils")
check "legacy NVIDIA: matching legacy 32-bit driver" '[[ $d == *" lib32-nvidia-470xx-utils" ]]'
d=$(drivers nvidia "")
check "NVIDIA without the proprietary driver: nouveau" '[[ $d == *"vulkan-nouveau lib32-vulkan-nouveau"* ]]'
d=$(drivers vm)
check "VM or unknown graphics: CPU Vulkan" '[[ $d == *"vulkan-swrast lib32-vulkan-swrast"* ]]'
check "drivers installed before the Yūrei packages" '[[ $(grep -n "^pacman -S " "$tmp/chroot-calls" | cut -d: -f1) -lt $(grep -n "^pacman -U " "$tmp/chroot-calls" | cut -d: -f1) ]]'
: > "$tmp/chroot-calls"
PATH="$tmp/bin:$PATH" YUREI_PKG_DIR="$tmp/pkgs" YUREI_SIGNING_KEY_FILE="$tmp/nokey" "$script" "$tmp/root"

check "packages copied into target" '[[ -f $tmp/root/var/cache/pacman/pkg/yurei-gaming-0.1.0-1-any.pkg.tar.zst ]]'
check "packages installed in one transaction" 'grep -q "^pacman -U --noconfirm --needed .*yurei-gaming.*yurei-settings\|^pacman -U --noconfirm --needed .*yurei-settings.*yurei-gaming" "$tmp/chroot-calls"'
check "regular users get GameMode" 'grep -qx "usermod -aG gamemode ana" "$tmp/chroot-calls"'
check "system users skipped" '! grep -q "usermod -aG gamemode \(root\|nobody\)" "$tmp/chroot-calls"'
check "Hello no longer starts itself" '[[ ! -e $tmp/root/home/ana/.config/autostart/cachyos-hello.desktop ]]'
check "other autostart entries kept" '[[ -e $tmp/root/home/ana/.config/autostart/other.desktop ]]'
check "installer-made accounts get the Yūrei theme" 'grep -qx "/usr/lib/yurei/theme-defaults /home/ana/.config/kdeglobals" "$tmp/chroot-calls"'
check "Limine entry renamed" 'grep -qx "/+Yurei" "$tmp/root/boot/limine.conf" && ! grep -q CachyOS "$tmp/root/boot/limine.conf"'
check "kernel entries untouched" 'grep -qx "  //linux-cachyos" "$tmp/root/boot/limine.conf"'
check "Limine wallpaper is Yūrei's" 'grep -qx "wallpaper: boot():/yurei-splash.png" "$tmp/root/boot/limine.conf" &&
    [[ $(cat "$tmp/root/boot/yurei-splash.png") == yurei ]]'
check "no repo without a key" '! grep -q "^\[yurei\]" "$tmp/root/etc/pacman.conf"'

: > "$tmp/chroot-calls"
PATH="$tmp/bin:$PATH" YUREI_PKG_DIR="$tmp/pkgs" YUREI_SIGNING_KEY_FILE="$tmp/yurei.asc" "$script" "$tmp/root"
check "key trusted by fingerprint" 'grep -qx "pacman-key --lsign-key $fpr" "$tmp/chroot-calls"'
check "signed repo configured" 'grep -qx "SigLevel = Required DatabaseRequired" "$tmp/root/etc/pacman.conf"'
check "temporary key removed" '[[ ! -e $tmp/root/tmp/yurei.asc ]]'
PATH="$tmp/bin:$PATH" YUREI_PKG_DIR="$tmp/pkgs" YUREI_SIGNING_KEY_FILE="$tmp/yurei.asc" "$script" "$tmp/root"
check "repo added only once" '[[ $(grep -c "^\[yurei\]" "$tmp/root/etc/pacman.conf") -eq 1 ]]'
check "refuses a non-system root" '! PATH="$tmp/bin:$PATH" YUREI_PKG_DIR="$tmp/pkgs" "$script" "$tmp/pkgs" 2>/dev/null'
exit $fail
