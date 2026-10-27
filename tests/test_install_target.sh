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
exit 0
STUB
chmod +x "$tmp/bin/arch-chroot"
touch "$tmp/pkgs/yurei-settings-0.1.0-1-any.pkg.tar.zst" "$tmp/pkgs/yurei-gaming-0.1.0-1-any.pkg.tar.zst"
printf 'root:x:0:0::/root:/bin/bash\nana:x:1000:1000::/home/ana:/bin/bash\nnobody:x:65534:65534::/:/usr/bin/nologin\n' > "$tmp/root/etc/passwd"
printf '[options]\n\n[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n' > "$tmp/root/etc/pacman.conf"

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
check "packages copied into target" '[[ -f $tmp/root/var/cache/pacman/pkg/yurei-gaming-0.1.0-1-any.pkg.tar.zst ]]'
check "packages installed in one transaction" 'grep -q "^pacman -U --noconfirm --needed .*yurei-gaming.*yurei-settings\|^pacman -U --noconfirm --needed .*yurei-settings.*yurei-gaming" "$tmp/chroot-calls"'
check "regular users get GameMode" 'grep -qx "usermod -aG gamemode ana" "$tmp/chroot-calls"'
check "system users skipped" '! grep -q "usermod -aG gamemode \(root\|nobody\)" "$tmp/chroot-calls"'
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
