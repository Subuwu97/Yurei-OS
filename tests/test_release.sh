#!/usr/bin/env bash
# The release version and codename in release.conf must match everything
# that shows them: both os-release files and the installer branding.
# checks are eval'd strings, so expansions are deliberately single-quoted
# shellcheck disable=SC2016,SC2034
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=release.conf
source "$here/release.conf"
codename=${RELEASE_CODENAME,,}

fail=0
check() {
    if eval "$2"; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

check "version is year.month" '[[ $RELEASE_VERSION =~ ^[0-9]{2}\.(0[1-9]|1[0-2])$ ]]'
check "codename is listed in docs/CODENAMES.md" 'grep -q "| \*\*$RELEASE_VERSION\*\* | \*\*$RELEASE_CODENAME\*\* |" "$here/docs/CODENAMES.md"'
for f in pkg/yurei-settings/files/usr/lib/yurei/os-release overlay/airootfs/etc/os-release; do
    check "$f: VERSION_ID" 'grep -qx "VERSION_ID=$RELEASE_VERSION" "$here/$f"'
    check "$f: VERSION_CODENAME" 'grep -qx "VERSION_CODENAME=$codename" "$here/$f"'
    check "$f: VERSION" 'grep -qx "VERSION=\"$RELEASE_VERSION ($RELEASE_CODENAME)\"" "$here/$f"'
    check "$f: PRETTY_NAME" 'grep -qx "PRETTY_NAME=\"Yūrei Linux $RELEASE_VERSION ($RELEASE_CODENAME)\"" "$here/$f"'
done
check "the two os-release files are the same" 'cmp -s "$here/pkg/yurei-settings/files/usr/lib/yurei/os-release" "$here/overlay/airootfs/etc/os-release"'
branding=$here/overlay/airootfs/usr/share/calamares/branding/yurei/branding.desc
check "installer shows the version" 'grep -q "version: *\"$RELEASE_VERSION ($RELEASE_CODENAME)\"" "$branding"'
check "installer shows the short version" 'grep -q "shortVersion: *\"$RELEASE_VERSION\"" "$branding"'
exit $fail
