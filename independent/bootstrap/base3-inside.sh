#!/bin/bash
# make variables below must stay literal
# shellcheck disable=SC2016
# Stage 2a, part 3: what makes the core tools a bootable system, built
# inside the Yūrei chroot (started by `chroot.sh base3-inside.sh`): systemd
# with udev, D-Bus, the final procps-ng and util-linux (both now know about
# systemd), the basic settings a system boots with, and Yūrei's own Linux
# kernel. boot-test.sh then boots it in QEMU.
#
# Follows Linux From Scratch's chapters 8 to 10 (systemd edition), without
# its patches: only upstream sources.
set -euo pipefail

# shellcheck source=independent/bootstrap/inside-lib.sh
source /bootstrap/inside-lib.sh

systemd_() {
    msg "systemd $(version systemd)"
    local src
    src=$(unpack systemd)
    mkdir "$src/build" && cd "$src/build"
    # firstboot off: it would stop the boot to ask questions on the console.
    # No home directories service, update service or boot loader yet; the
    # users and groups units need come from systemd-sysusers at boot.
    meson setup .. --prefix=/usr --buildtype=release -D mode=release \
        -D default-dnssec=no -D firstboot=false -D install-tests=false -D tests=false \
        -D ldconfig=false -D rpmmacrosdir=no -D homed=disabled -D userdb=false \
        -D man=disabled -D pamconfdir=no -D dev-kvm-mode=0660 -D nobody-group=nogroup \
        -D sysupdate=disabled -D ukify=disabled -D bootloader=disabled \
        -D docdir="/usr/share/doc/systemd-$(version systemd)"
    ninja
    ninja install
    # services start as upstream's presets say (networkd, resolved, getty, …)
    systemctl preset-all
}

dbus() {
    msg "D-Bus $(version dbus)"
    local src
    src=$(unpack dbus)
    mkdir "$src/build" && cd "$src/build"
    meson setup .. --prefix=/usr --buildtype=release --wrap-mode=nofallback
    ninja
    ninja install
    mkdir -p /var/lib/dbus
    ln -sf /etc/machine-id /var/lib/dbus/machine-id
}

procps() {
    msg "procps-ng $(version procps-ng)"
    local src
    src=$(unpack procps-ng)
    cd "$src"
    # kill comes from util-linux
    ./configure --prefix=/usr --docdir="/usr/share/doc/procps-ng-$(version procps-ng)" \
        --disable-static --disable-kill --enable-watch8bit --with-systemd
    make src_w_LDADD='$(LDADD) -lsystemd'
    make install
}

util_linux() {
    msg "util-linux $(version util-linux), final"
    local src
    src=$(unpack util-linux)
    cd "$src"
    # login, nologin, su and chfn/chsh come from shadow
    ./configure --bindir=/usr/bin --libdir=/usr/lib --runstatedir=/run --sbindir=/usr/sbin \
        --disable-chfn-chsh --disable-login --disable-nologin --disable-su --disable-setpriv \
        --disable-runuser --disable-pylibmount --disable-liblastlog2 --disable-static \
        --without-python ADJTIME_PATH=/var/lib/hwclock/adjtime \
        --docdir="/usr/share/doc/util-linux-$(version util-linux)"
    make
    make install
}

# The settings a Yūrei system boots with. Nothing machine-specific: the
# machine ID is made at first boot, the network is set up by DHCP.
system_config() {
    msg "System settings"
    cat > /etc/os-release <<'OS'
NAME="Yūrei Linux"
PRETTY_NAME="Yūrei Linux (independent preview)"
ID=yurei
ANSI_COLOR="38;2;185;170;255"
HOME_URL="https://github.com/Subuwu97/Yurei-OS"
OS
    ln -sf ../etc/os-release /usr/lib/os-release
    # the kernel starts /sbin/init
    [[ -e /usr/sbin/init ]] || ln -s ../lib/systemd/systemd /usr/sbin/init
    echo yurei > /etc/hostname
    echo LANG=C.UTF-8 > /etc/locale.conf
    echo KEYMAP=us > /etc/vconsole.conf
    # the root file system comes from the kernel command line (root=)
    cat > /etc/fstab <<'FSTAB'
# file system  mount point  type  options  dump  fsck
# The root file system is the one named on the kernel command line.
FSTAB
    printf '/bin/sh\n/bin/bash\n/usr/bin/sh\n/usr/bin/bash\n' > /etc/shells
    # wired networks get an address by DHCP; names resolve through resolved
    mkdir -p /etc/systemd/network
    cat > /etc/systemd/network/20-wired.network <<'NET'
[Match]
Type=ether

[Network]
DHCP=yes
NET
    ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    # empty: systemd makes a unique machine ID at first boot
    : > /etc/machine-id
}

kernel() {
    local src release
    msg "Linux $(version linux), Yūrei's kernel"
    src=$(unpack linux)
    cd "$src"
    make mrproper
    # the kernel's own defaults for x86-64, plus what virtual machines need,
    # plus what systemd needs
    make defconfig
    make kvm_guest.config
    scripts/config -e DEVTMPFS -e DEVTMPFS_MOUNT -e CGROUPS -e MEMCG -e FHANDLE \
        -e AUTOFS_FS -e TMPFS_POSIX_ACL -e TMPFS_XATTR -e SECCOMP -e BPF_SYSCALL \
        -e CGROUP_BPF -e PSI -e DMIID -e INOTIFY_USER -e EXT4_FS -e VIRTIO_BLK \
        -e VIRTIO_NET -e SERIAL_8250_CONSOLE -d UEVENT_HELPER -d SYSFS_DEPRECATED \
        --set-str LOCALVERSION -yurei -d LOCALVERSION_AUTO
    make olddefconfig
    make -j"$(nproc)"
    release=$(make -s kernelrelease)
    make INSTALL_MOD_STRIP=1 modules_install
    mkdir -p /boot
    cp arch/x86/boot/bzImage "/boot/vmlinuz-$release"
    cp System.map "/boot/System.map-$release"
    cp .config "/boot/config-$release"
    cd / && rm -rf "$src"
}

check() {
    msg "Checking the bootable system"
    systemctl --version | head -n1
    dbus-daemon --version | head -n1
    ps --version
    mount --version
    ls -l /boot
    local modules
    modules=$(find /usr/lib/modules -name '*.ko*' | wc -l)
    echo "kernel modules: $modules"
    [[ $(readlink -f /sbin/init) == /usr/lib/systemd/systemd ]] || { echo "/sbin/init isn't systemd" >&2; exit 1; }
    compgen -G '/boot/vmlinuz-*' >/dev/null || { echo "no kernel in /boot" >&2; exit 1; }
    systemctl is-enabled systemd-networkd.service getty@tty1.service
    local missing
    missing=$(find /usr/bin /usr/sbin /usr/lib /usr/lib/systemd -maxdepth 1 -type f -perm -u+x -exec ldd {} + 2>/dev/null |
        grep 'not found' | sort -u || true)
    [[ -z $missing ]] || { echo "missing libraries:"$'\n'"$missing" >&2; exit 1; }
    echo "bootable system OK"
}

STEPS=(systemd_ dbus procps util_linux system_config kernel check)
run_steps "$@"
