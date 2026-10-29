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

# everything in the new system belongs to root from now on
chown -R root:root "$YUREI"/{usr,var,etc,tools,lib64}
chown -h root:root "$YUREI"/{bin,lib,sbin}

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
# the sources and the build scripts, read-only, so the build can't change them
mnt /sources --bind -o ro "$SOURCES"
mnt /bootstrap --bind -o ro "$here"

inside=chroot-inside.sh
if [[ ${1:-} == *.sh ]]; then
    inside=$1
    shift
fi
[[ -f $here/$inside ]] || { echo "no such script: $inside" >&2; exit 1; }

chroot "$YUREI" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
    MAKEFLAGS="-j$(nproc)" LC_ALL=POSIX \
    /bin/bash "/bootstrap/$inside" "$@"
