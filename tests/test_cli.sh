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
printf 'var yureiLayout_test = 1;\n' > "$tmp/layout.js"
cat > "$tmp/bin/qdbus6" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$tmp/qdbus-args"
STUB
chmod +x "$tmp/bin/qdbus6"
if [[ $EUID -eq 0 ]]; then
    check "layout refuses to run as root" '! YUREI_LAYOUT_SCRIPT=$tmp/layout.js "$yurei" layout dock 2>/dev/null'
else
    YUREI_LAYOUT_SCRIPT=$tmp/layout.js "$yurei" layout dock >/dev/null
    check "layout runs Plasma's scripting with the mode set" 'grep -q "evaluateScript" "$tmp/qdbus-args" && grep -q "var yureiLayout = \"dock\";" "$tmp/qdbus-args"'
fi
check "layout rejects unknown modes" '! "$yurei" layout sideways 2>/dev/null'
cat > "$tmp/bin/plasma-apply-lookandfeel" <<STUB
#!/bin/sh
echo "plasma-apply-lookandfeel \$*" >> "$tmp/calls"
STUB
chmod +x "$tmp/bin/plasma-apply-lookandfeel"
if [[ $EUID -eq 0 ]]; then
    check "theme refuses to run as root" '! "$yurei" theme yurei 2>/dev/null'
else
    : > "$tmp/calls"
    "$yurei" theme yurei >/dev/null
    check "theme applies the Yūrei global theme" 'grep -qx "plasma-apply-lookandfeel --apply org.yurei.desktop" "$tmp/calls"'
fi
check "theme rejects unknown themes" '! "$yurei" theme plaid 2>/dev/null'
# Linux environments, with distrobox replaced by a stub that has "ubuntu" already
cat > "$tmp/bin/distrobox" <<STUB
#!/bin/sh
echo "distrobox \$*" >> "$tmp/calls"
[ "\$1" = list ] && printf 'ID           | NAME   | STATUS | IMAGE\nabc123       | ubuntu | Up     | ubuntu:latest\n'
# a real create reads its terminal; this one would eat the list it's given
[ "\$1" = create ] && cat > /dev/null
exit 0
STUB
for cmd in podman notify-send; do printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n' "$cmd" "$tmp" > "$tmp/bin/$cmd"; done
chmod +x "$tmp/bin/distrobox" "$tmp/bin/podman" "$tmp/bin/notify-send"
check "box rejects unknown environments" '! "$yurei" box add plan9 2>/dev/null'
if [[ $EUID -eq 0 ]]; then
    check "box refuses to run as root" '! "$yurei" box add fedora 2>/dev/null'
else
    : > "$tmp/calls"
    "$yurei" box add fedora >/dev/null
    check "box add creates and sets up the environment" 'grep -qx "distrobox create --yes --name fedora --image registry.fedoraproject.org/fedora:latest" "$tmp/calls" &&
        grep -qx "distrobox enter fedora -- true" "$tmp/calls"'
    check "box add needs no packages when Distrobox is there" '! grep -q "^pacman" "$tmp/calls"'
    : > "$tmp/calls"
    "$yurei" box add ubuntu >/dev/null
    check "box add leaves an existing environment alone" '! grep -q "distrobox create" "$tmp/calls"'
    printf 'ubuntu\nfedora\nnope\narch\n' > "$tmp/boxes"
    : > "$tmp/calls"
    YUREI_BOXES_FILE=$tmp/boxes "$yurei" box setup
    check "login setup creates the missing environments, in order" '[[ $(grep "distrobox create" "$tmp/calls" | grep -o "name [a-z]*") == $'"'"'name fedora\nname arch'"'"' ]]'
    check "login setup tells the user" 'grep -q "^notify-send .*Arch (pacman) is ready" "$tmp/calls"'
    : > "$tmp/calls"
    YUREI_BOXES_FILE=$tmp/none "$yurei" box setup
    check "login setup does nothing without a list" '[[ ! -s $tmp/calls ]]'
fi
files=$here/pkg/yurei-settings/files
wine_types=$(sed -n 's/^MimeType=//p' "$files/usr/share/applications/yurei-wine.desktop")
check "Windows programs open with Wine by default" '
    while IFS="=" read -r type app; do
        [[ $type == application/* ]] || continue
        [[ ${app%;} == yurei-wine.desktop && ";$wine_types" == *";$type;"* ]] || exit 1
    done < "$files/etc/xdg/mimeapps.list"'
check "the Wine launcher runs the program from its folder" 'grep -qx "Exec=wine start /unix %f" "$files/usr/share/applications/yurei-wine.desktop"'
check "version prints" '[[ $("$yurei" version) =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]'
exit $fail
