#!/usr/bin/env bash
# yurei-install (the live desktop's "Install Yūrei") with curl and the
# installer script replaced by stubs.
# checks are eval'd strings, so expansions are deliberately single-quoted
# shellcheck disable=SC2016,SC2034
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script=$here/overlay/airootfs/usr/local/bin/yurei-install
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
export XDG_RUNTIME_DIR=$tmp YUREI_INSTALL_LOG=$tmp/install.log YUREI_INSTALLER=$tmp/installer

fail=0
check() {
    if eval "$2"; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

# curl succeeds once a "network" file exists
cat > "$tmp/bin/curl" <<STUB
#!/bin/sh
echo curl >> "$tmp/calls"
[ -e "$tmp/network" ]
STUB
printf '#!/bin/sh\necho installer >> "%s/calls"\nexit "${INSTALLER_STATUS:-0}"\n' "$tmp" > "$tmp/installer"
chmod +x "$tmp/bin/curl" "$tmp/installer"
export PATH=$tmp/bin:$PATH

touch "$tmp/network"
out=$("$script" < /dev/null)
check "online: starts the installer" 'grep -qx installer "$tmp/calls"'
check "explains the wait" 'grep -q "takes a minute or two" <<< "$out"'

rm "$tmp/network" "$tmp/calls"
# offline at first: Enter is pressed once the network is up
out=$( { sleep 0.3; touch "$tmp/network"; echo; } | "$script")
check "offline: says so and waits" 'grep -q "No internet connection" <<< "$out"'
check "then starts the installer once online" 'grep -qx installer "$tmp/calls"'

echo "error: failed to commit transaction" > "$tmp/install.log"
out=$(INSTALLER_STATUS=1 "$script" < /dev/null)
check "a failure shows the log" 'grep -q "stopped (code 1)" <<< "$out" && grep -q "failed to commit" <<< "$out"'

exec 8>"$tmp/yurei-install.lock"
flock 8
: > "$tmp/calls"
out=$("$script" < /dev/null)
check "a second click doesn't start a second installer" 'grep -q "already starting" <<< "$out" && ! grep -q installer "$tmp/calls"'
exit $fail
