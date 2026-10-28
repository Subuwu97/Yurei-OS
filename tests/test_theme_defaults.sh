#!/usr/bin/env bash
# theme-defaults against copies of CachyOS's skel kdeglobals and edge cases.
# checks are eval'd strings, so expansions are deliberately single-quoted
# shellcheck disable=SC2016
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script=$here/pkg/yurei-settings/files/usr/lib/yurei/theme-defaults
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
check() {
    if eval "$2"; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

# as cachyos-kde-settings ships it
printf '[General]\nColorScheme=BreezeDark\n\n[Icons]\nTheme=breeze-dark\n\n[KDE]\nAnimationDurationFactor=0.25\nwidgetStyle=Breeze\n' > "$tmp/cachyos"
"$script" "$tmp/cachyos"
check "colour scheme switched" 'grep -qx "ColorScheme=Yurei" "$tmp/cachyos" && ! grep -q BreezeDark "$tmp/cachyos"'
check "global theme set in [KDE]" '[[ $(sed -n "/^\[KDE\]/,/^\[/p" "$tmp/cachyos") == *LookAndFeelPackage=org.yurei.desktop* ]]'
check "other settings kept" 'grep -qx "AnimationDurationFactor=0.25" "$tmp/cachyos" && grep -qx "Theme=breeze-dark" "$tmp/cachyos"'
cp "$tmp/cachyos" "$tmp/once"
"$script" "$tmp/cachyos"
check "running twice changes nothing" 'cmp -s "$tmp/cachyos" "$tmp/once"'

printf '[Colors:View]\nBackgroundNormal=1,2,3\n' > "$tmp/nogroups"
"$script" "$tmp/nogroups"
check "missing groups are added" 'grep -qx "\[General\]" "$tmp/nogroups" && grep -qx "LookAndFeelPackage=org.yurei.desktop" "$tmp/nogroups" &&
    grep -qx "BackgroundNormal=1,2,3" "$tmp/nogroups"'

printf '[General]\nColorSchemeHash=abc\nColorScheme=BreezeLight\n' > "$tmp/prefix"
"$script" "$tmp/prefix"
check "similar keys left alone" 'grep -qx "ColorSchemeHash=abc" "$tmp/prefix" && [[ $(grep -c "^ColorScheme=" "$tmp/prefix") -eq 1 ]]'

chmod 600 "$tmp/prefix"
"$script" "$tmp/prefix"
check "file mode kept" '[[ $(stat -c %a "$tmp/prefix") == 600 ]]'
check "missing files are skipped" '"$script" "$tmp/does-not-exist"'
exit $fail
