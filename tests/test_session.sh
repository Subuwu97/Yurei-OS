#!/usr/bin/env bash
# Tests session-select against throwaway login-manager config directories.
# checks are eval'd strings, so expansions are deliberately single-quoted
# shellcheck disable=SC2016,SC2034
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper=$here/pkg/yurei-settings/files/usr/lib/yurei/session-select
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/plasmalogin.conf.d"   # installed login manager
# "$tmp/sddm.conf.d" deliberately absent: SDDM isn't installed

run() {
    local root=()
    [[ $EUID -eq 0 ]] || root=(sudo)
    "${root[@]}" env YUREI_DM_CONF_DIRS="$tmp/plasmalogin.conf.d $tmp/sddm.conf.d" \
        SUDO_USER="${TEST_USER:-nobody}" "$helper" "$@"
}

fail=0
check() {
    if eval "$2"; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}
conf=$tmp/plasmalogin.conf.d/zz-yurei-session.conf

run game >/dev/null
check "game mode autologin" 'grep -qx "Session=yurei-steam.desktop" "$conf" && grep -qx "Relogin=true" "$conf"'
check "autologin user" 'grep -qx "User=nobody" "$conf"'
check "missing login managers untouched" '[[ ! -e $tmp/sddm.conf.d ]]'
run desktop >/dev/null
check "switch to desktop" 'grep -qx "Session=plasma.desktop" "$conf"'
run off >/dev/null
check "off removes autologin" '[[ ! -e $conf ]]'
check "bad mode rejected" '! run hack 2>/dev/null'
check "system users rejected" '! TEST_USER=root run game 2>/dev/null'
exit $fail
