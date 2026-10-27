#!/usr/bin/env bash
# Exercises the yurei CLI with pacman/flatpak/sudo replaced by recording stubs.
# checks are eval'd strings, so expansions are deliberately single-quoted
# shellcheck disable=SC2016,SC2034
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
yurei=$here/pkg/yurei-settings/files/usr/bin/yurei
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/bin"
for cmd in pacman flatpak sudo paru; do
    cat > "$tmp/bin/$cmd" <<STUB
#!/bin/sh
echo "$cmd \$*" >> "$tmp/calls"
[ "$cmd" = sudo ] && exec "\$@"
exit 0
STUB
    chmod +x "$tmp/bin/$cmd"
done
export PATH="$tmp/bin:$PATH" YUREI_BUNDLE_DIR="$here/pkg/yurei-settings/files/usr/share/yurei/bundles"

fail=0
check() {
    if eval "$2"; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

out=$("$yurei" bundles)
check "bundles lists every bundle" '[[ $(grep -c "^  [a-z]" <<< "$out") -eq $(ls "$YUREI_BUNDLE_DIR"/*.list | wc -l) ]]'
check "bundles show descriptions" 'grep -q "emulation .*RetroArch" <<< "$out"'

: > "$tmp/calls"
"$yurei" install streaming emulation >/dev/null
check "repo packages installed in one transaction" 'grep -Eq "^(paru|pacman) -S --needed obs-studio .*retroarch" "$tmp/calls"'
check "flatpaks installed from flathub" 'grep -q "^flatpak install -y flathub .*net.pcsx2.PCSX2" "$tmp/calls"'
check "flathub added first" 'grep -q "^flatpak remote-add --if-not-exists flathub" "$tmp/calls"'
check "comments are not packages" '! grep -q "description" "$tmp/calls"'

check "unknown bundle fails" '! "$yurei" install nope 2>/dev/null'
check "path traversal rejected" '! "$yurei" install ../../etc/passwd 2>/dev/null'
check "unknown command fails" '! "$yurei" frobnicate 2>/dev/null'
check "version prints" '[[ $("$yurei" version) =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]'
exit $fail
