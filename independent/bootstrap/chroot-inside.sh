#!/bin/bash
# Runs inside the new Yūrei system (started by chroot.sh, not by hand).
# Only Yūrei's own programs are available here: everything below is built
# by Yūrei's own compiler, from /sources, with /bootstrap's recipes.
set -euo pipefail

# shellcheck source=independent/bootstrap/inside-lib.sh
source /bootstrap/inside-lib.sh

# the directory tree and the files every Linux system expects
basics() {
    msg "Directories, accounts and log files"
    mkdir -p /{boot,home,mnt,opt,srv} /etc/{opt,sysconfig} /lib/firmware /media/{floppy,cdrom}
    mkdir -p /usr/{,local/}{include,src} /usr/lib/locale /usr/local/{bin,lib,sbin}
    mkdir -p /usr/{,local/}share/{color,dict,doc,info,locale,man,misc,terminfo,zoneinfo}
    mkdir -p /usr/{,local/}share/man/man{1..8}
    mkdir -p /var/{cache,local,log,mail,opt,spool} /var/lib/{color,misc,locate}
    ln -sfn /run /var/run
    ln -sfn /run/lock /var/lock
    install -d -m 0750 /root
    install -d -m 1777 /tmp /var/tmp
    ln -sf /proc/self/mounts /etc/mtab
    cat > /etc/hosts <<'HOSTS'
127.0.0.1  localhost yurei
::1        localhost
HOSTS
    cat > /etc/passwd <<'PASSWD'
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
PASSWD
    cat > /etc/group <<'GROUP'
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
GROUP
    touch /var/log/{btmp,lastlog,faillog,wtmp}
    chgrp utmp /var/log/lastlog
    chmod 664 /var/log/lastlog
    chmod 600 /var/log/btmp
}

gettext_() {
    msg "gettext $(version gettext) (only the tools the builds need)"
    local src
    src=$(unpack gettext)
    cd "$src"
    ./configure --disable-shared
    make
    cp gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
}

bison_() {
    msg "bison $(version bison)"
    local src
    src=$(unpack bison)
    cd "$src"
    ./configure --prefix=/usr --docdir="/usr/share/doc/bison-$(version bison)"
    make
    make install
}

perl_() {
    msg "perl $(version perl)"
    local src v
    src=$(unpack perl)
    v=$(version perl | cut -d. -f1,2)
    cd "$src"
    sh Configure -des -D prefix=/usr -D vendorprefix=/usr -D useshrplib \
        -D privlib="/usr/lib/perl5/$v/core_perl" -D archlib="/usr/lib/perl5/$v/core_perl" \
        -D sitelib="/usr/lib/perl5/$v/site_perl" -D sitearch="/usr/lib/perl5/$v/site_perl" \
        -D vendorlib="/usr/lib/perl5/$v/vendor_perl" -D vendorarch="/usr/lib/perl5/$v/vendor_perl"
    make
    make install
}

python_() {
    msg "Python $(version Python)"
    local src
    src=$(unpack Python)
    cd "$src"
    ./configure --prefix=/usr --enable-shared --without-ensurepip --without-static-libpython
    make
    make install
}

texinfo_() {
    msg "texinfo $(version texinfo)"
    local src
    src=$(unpack texinfo)
    cd "$src"
    ./configure --prefix=/usr
    make
    make install
}

util_linux() {
    msg "util-linux $(version util-linux)"
    local src
    src=$(unpack util-linux)
    mkdir -p /var/lib/hwclock
    cd "$src"
    ./configure --libdir=/usr/lib --runstatedir=/run \
        --disable-chfn-chsh --disable-login --disable-nologin --disable-su \
        --disable-setpriv --disable-runuser --disable-pylibmount --disable-static \
        --disable-liblastlog2 --without-python ADJTIME_PATH=/var/lib/hwclock/adjtime \
        --docdir="/usr/share/doc/util-linux-$(version util-linux)"
    make
    make install
}

# Proof that Yūrei now builds software by itself: compile and run a C and a
# C++ program here, with Yūrei's own compiler and libraries only.
check() {
    msg "Checking that Yūrei builds by itself"
    local dir
    dir=$(mktemp -d)
    printf '#include <stdio.h>\nint main(void) { puts("built inside Yūrei"); return 0; }\n' > "$dir/hello.c"
    printf '#include <iostream>\nint main() { std::cout << "C++ built inside Yūrei\\n"; }\n' > "$dir/hello.cpp"
    gcc "$dir/hello.c" -o "$dir/hello" && "$dir/hello"
    g++ "$dir/hello.cpp" -o "$dir/hello-cpp" && "$dir/hello-cpp"
    rm -rf "$dir"
    local tool
    for tool in msgfmt bison perl python3 makeinfo mount; do
        command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
    done
    perl -e 'print "perl $^V\n"'
    python3 -c 'import sys; print("Python", sys.version.split()[0])'
    echo "chroot tools OK"
}

# the temporary toolchain and documentation aren't needed any more
cleanup() {
    msg "Cleaning up"
    rm -rf /usr/share/{info,man,doc}/*
    find /usr/{lib,libexec} -name '*.la' -delete
    rm -rf /tools "$build"
}

STEPS=(basics gettext_ bison_ perl_ python_ texinfo_ util_linux check cleanup)
run_steps "$@"
