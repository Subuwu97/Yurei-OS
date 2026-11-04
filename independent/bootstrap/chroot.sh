#!/usr/bin/env bash
# The chroot step, after temptools.sh: from here on Yūrei builds itself.
#
# Hands $YUREI to root, mounts the kernel's virtual filesystems into it,
# and runs chroot-inside.sh inside it with chroot. Inside, only Yūrei's own
# programs exist; the host provides nothing but the running kernel. That
# script sets up the basic directories and accounts and builds the last
# tools the full system build needs (gettext, bison, perl, Python, texinfo,
# util-linux). Follows Linux From Scratch's method; needs root.
#
#   sudo YUREI=/path/to/root SOURCES=/path/to/sources ./chroot.sh [SCRIPT] [STEP...]
#
# SCRIPT is the script to run inside (default chroot-inside.sh), e.g.
# base-inside.sh for the base system.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
YUREI=${YUREI:?set YUREI to the directory built by stage1.sh and temptools.sh}
SOURCES=${SOURCES:?set SOURCES to the directory fetch.sh downloaded into}
[[ $EUID -eq 0 ]] || { echo "chroot.sh needs root (sudo)" >&2; exit 1; }
[[ -x $YUREI/usr/bin/bash && -x $YUREI/usr/bin/gcc ]] || { echo "run temptools.sh first" >&2; exit 1; }

inside=chroot-inside.sh
if [[ ${1:-} == *.sh ]]; then
    inside=$1
    shift
fi
[[ -f $here/$inside ]] || { echo "no such script: $inside" >&2; exit 1; }

# Only the initial toolchain handoff changes ownership. Repeating chown on
# a packaged system clears setuid/setgid bits (even root -> root), breaking
# sudo and other privileged helpers in the staged live image.
if [[ $inside == chroot-inside.sh ]]; then
    for dir in usr var etc tools lib64; do
        [[ -e $YUREI/$dir ]] && chown -R root:root "$YUREI/$dir"
    done
    chown -h root:root "$YUREI"/{bin,lib,sbin}
fi

mounted=()
mnt() {  # mnt TARGET MOUNT-ARGS...: mount once, remember it for unmounting
    local target=$YUREI$1
    shift
    mkdir -p "$target"
    mountpoint -q "$target" || { mount "$@" "$target"; mounted+=("$target"); }
}
cleanup() {
    local i
    for (( i = ${#mounted[@]} - 1; i >= 0; i-- )); do
        umount -l "${mounted[i]}" || true
    done
}
trap cleanup EXIT

mnt /dev --bind /dev
mnt /dev/pts -t devpts devpts -o gid=5,mode=0620
mnt /proc -t proc proc
mnt /sys -t sysfs sysfs
mnt /run -t tmpfs tmpfs
# Optional persistent signing home, separate from all disposable build roots.
# Only the integration workflow supplies it; private keys never enter an ISO.
if [[ -n ${YUREI_SIGNING_HOME:-} ]]; then
    [[ $YUREI_SIGNING_HOME == /* && -d $YUREI_SIGNING_HOME ]] || { echo "invalid signing home" >&2; exit 1; }
    mnt /signing-gnupg --bind "$YUREI_SIGNING_HOME"
fi
# Reusable app deployments are outside the disposable ISO staging tree.
if [[ -n ${YUREI_APP_STORE:-} ]]; then
    [[ $YUREI_APP_STORE == /* && -d $YUREI_APP_STORE ]] || { echo "invalid app store" >&2; exit 1; }
    mnt /var/lib/flatpak --bind "$YUREI_APP_STORE"
    # The staged image uses systemd-resolved, but no services run in this
    # build chroot. Supply DNS in its temporary /run only; unmounting /run
    # removes it before packing the live image.
    mkdir -p "$YUREI/run/systemd/resolve"
    cp -L /etc/resolv.conf "$YUREI/run/systemd/resolve/stub-resolv.conf"
fi
# the sources and the build scripts, read-only, so the build can't change them
mnt /sources --bind -o ro "$SOURCES"
mnt /bootstrap --bind -o ro "$here"

chroot "$YUREI" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
    MAKEFLAGS="-j$(nproc)" LC_ALL=POSIX \
    /bin/bash "/bootstrap/$inside" "$@"
