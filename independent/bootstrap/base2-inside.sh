#!/bin/bash
# sed scripts below edit Makefiles, whose $(VARS) must stay literal
# shellcheck disable=SC2016
# Stage 2a, part 2: the rest of the core tools, built inside the Yūrei
# chroot with the final toolchain from part 1 (started by
# `chroot.sh base2-inside.sh`). The shell, the scripting languages, the
# build systems (autotools, meson, ninja), OpenSSL, and the everyday
# command-line tools. systemd, the kernel and the tools that build on
# systemd (procps-ng, util-linux) come in part 3.
#
# Follows Linux From Scratch's chapter 8 (systemd edition), without its
# own patches: only upstream sources. Test suites are left out for now.
set -euo pipefail

# shellcheck source=independent/bootstrap/inside-lib.sh
source /bootstrap/inside-lib.sh

ncurses_() {
    msg "ncurses $(version ncurses), final"
    local src lib
    src=$(unpack ncurses)
    cd "$src"
    # GCC 15 defaults to C23, where bool is a keyword; ncurses 6.5 predates that
    CC="gcc -std=gnu17" ./configure --prefix=/usr --mandir=/usr/share/man --with-shared \
        --without-debug --without-normal --with-cxx-shared --enable-pc-files \
        --with-pkg-config-libdir=/usr/lib/pkgconfig
    make
    make DESTDIR="$PWD/dest" install
    # replace the library the running shell uses in one step
    install -m755 "dest/usr/lib/libncursesw.so.$(version ncurses)" /usr/lib
    rm "dest/usr/lib/libncursesw.so.$(version ncurses)"
    # the wide-character library is the only one; say so in the header
    sed -e 's/^#if.*XOPEN.*$/#if 1/' -i dest/usr/include/curses.h
    cp -a dest/* /
    for lib in ncurses form panel menu; do
        ln -sf "lib${lib}w.so" "/usr/lib/lib${lib}.so"
        ln -sf "${lib}w.pc" "/usr/lib/pkgconfig/${lib}.pc"
    done
    ln -sf libncursesw.so /usr/lib/libcurses.so
}

sed_() { build_simple sed; }
psmisc_() { build_simple psmisc; }

gettext_() {
    build_simple gettext --disable-static --docdir="/usr/share/doc/gettext-$(version gettext)"
    chmod 0755 /usr/lib/preloadable_libintl.so
}

bison_() { build_simple bison --docdir="/usr/share/doc/bison-$(version bison)"; }

grep_() {
    msg "grep $(version grep)"
    local src
    src=$(unpack grep)
    cd "$src"
    sed -i "s/echo/#echo/" src/egrep.sh  # no "egrep is obsolescent" warning
    ./configure --prefix=/usr
    make
    make install
}

bash_() {
    build_simple bash --without-bash-malloc --with-installed-readline \
        --docdir="/usr/share/doc/bash-$(version bash)"
}

libtool_() {
    build_simple libtool
    rm -f /usr/lib/libltdl.a
}

gdbm() { build_simple gdbm --disable-static --enable-libgdbm-compat; }
gperf_() { build_simple gperf --docdir="/usr/share/doc/gperf-$(version gperf)"; }
expat() { build_simple expat --disable-static --docdir="/usr/share/doc/expat-$(version expat)"; }
less_() { build_simple less --sysconfdir=/etc; }

perl_() {
    msg "perl $(version perl), final"
    local src v
    src=$(unpack perl)
    v=$(version perl | cut -d. -f1,2)
    cd "$src"
    # use the system's zlib and bzip2, not perl's bundled copies
    BUILD_ZLIB=False BUILD_BZIP2=0 sh Configure -des -D prefix=/usr -D vendorprefix=/usr \
        -D privlib="/usr/lib/perl5/$v/core_perl" -D archlib="/usr/lib/perl5/$v/core_perl" \
        -D sitelib="/usr/lib/perl5/$v/site_perl" -D sitearch="/usr/lib/perl5/$v/site_perl" \
        -D vendorlib="/usr/lib/perl5/$v/vendor_perl" -D vendorarch="/usr/lib/perl5/$v/vendor_perl" \
        -D man1dir=/usr/share/man/man1 -D man3dir=/usr/share/man/man3 \
        -D pager="/usr/bin/less -isR" -D useshrplib -D usethreads
    BUILD_ZLIB=False BUILD_BZIP2=0 make
    make install
}

autoconf_() { build_simple autoconf; }
automake_() { build_simple automake --docdir="/usr/share/doc/automake-$(version automake)"; }

openssl_() {
    msg "OpenSSL $(version openssl)"
    local src
    src=$(unpack openssl)
    cd "$src"
    ./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
    make
    # libraries, headers, tools and /etc/ssl; no static libraries or HTML manuals
    sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
    make install_sw install_ssldirs
}

# only libelf: the kernel and systemd need it, the rest of elfutils isn't needed yet
elfutils() {
    msg "elfutils $(version elfutils) (libelf)"
    local src
    src=$(unpack elfutils)
    cd "$src"
    ./configure --prefix=/usr --disable-debuginfod --enable-libdebuginfod=dummy
    make
    make -C libelf install
    install -m644 config/libelf.pc /usr/lib/pkgconfig
    rm -f /usr/lib/libelf.a
}

# --with-gcc-arch=x86-64: runs on any x86-64 CPU, not just the build machine's
libffi() { build_simple libffi --disable-static --with-gcc-arch=x86-64; }

python_() {
    msg "Python $(version Python), final"
    local src
    src=$(unpack Python)
    cd "$src"
    # now with OpenSSL, libffi and expat; pip comes with it (from the
    # tarball, nothing downloaded) to install the Python packages below
    ./configure --prefix=/usr --enable-shared --with-system-expat --without-static-libpython
    make
    make install
    python3 -c 'import ssl, ctypes, bz2, lzma, zlib, readline, pyexpat'
}

# python_package NAME: builds a wheel from the source tarball and installs
# it, offline and without build isolation (the build tools are installed
# here in order)
python_package() {
    local name=$1 src
    msg "$name $(version "$name")"
    src=$(unpack "$name")
    cd "$src"
    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
    pip3 install --no-index --no-user --find-links dist "$name"
}

flit_core() { python_package flit_core; }
packaging() { python_package packaging; }  # wheel needs it
wheel_() { python_package wheel; }
setuptools() { python_package setuptools; }
markupsafe() { python_package markupsafe; }
jinja2() { python_package jinja2; }
meson_() { python_package meson; }

ninja_() {
    msg "ninja $(version ninja)"
    local src
    src=$(unpack ninja)
    cd "$src"
    python3 configure.py --bootstrap
    install -m755 ninja /usr/bin/
}

kmod_() {
    msg "kmod $(version kmod)"
    local src
    src=$(unpack kmod)
    cd "$src"
    # manual pages need scdoc, which isn't here yet
    meson setup --prefix=/usr --buildtype=release -D manpages=false build
    ninja -C build
    ninja -C build install
}

coreutils_() {
    msg "coreutils $(version coreutils), final"
    local src
    src=$(unpack coreutils)
    cd "$src"
    # kill and uptime come from procps-ng
    FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr --enable-no-install-program=kill,uptime
    make
    make install
    mv /usr/bin/chroot /usr/sbin
}

diffutils_() { build_simple diffutils; }

gawk_() {
    msg "gawk $(version gawk), final"
    local src
    src=$(unpack gawk)
    cd "$src"
    sed -i 's/extras//' Makefile.in  # no extra example scripts
    ./configure --prefix=/usr
    make
    rm -f /usr/bin/gawk-"$(version gawk)"
    make install
}

findutils_() { build_simple findutils --localstatedir=/var/lib/locate; }
gzip_() { build_simple gzip; }

iproute2_() {
    msg "iproute2 $(version iproute2)"
    local src
    src=$(unpack iproute2)
    cd "$src"
    # arpd needs Berkeley DB, which Yūrei doesn't have
    sed -i /ARPD/d Makefile
    rm -f man/man8/arpd.8
    make NETNS_RUN_DIR=/run/netns
    make SBINDIR=/usr/sbin install
}

kbd_() {
    msg "kbd $(version kbd)"
    local src
    src=$(unpack kbd)
    cd "$src"
    # resizecons needs svgalib, which is long gone
    sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
    [[ ! -f docs/man/man8/Makefile.in ]] || sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
    ./configure --prefix=/usr --disable-vlock
    make
    make install
}

make_() { build_simple make; }
patch_() { build_simple patch; }

tar_() {
    msg "tar $(version tar), final"
    local src
    src=$(unpack tar)
    cd "$src"
    FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
    make
    make install
}

texinfo_() { build_simple texinfo; }

e2fsprogs_() {
    msg "e2fsprogs $(version e2fsprogs)"
    local src
    src=$(unpack e2fsprogs)
    mkdir "$src/build" && cd "$src/build"
    # libblkid, libuuid and fsck come from util-linux
    ../configure --prefix=/usr --sysconfdir=/etc --enable-elf-shlibs \
        --disable-libblkid --disable-libuuid --disable-uuidd --disable-fsck
    make
    make install
    rm -f /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
}

# Everything new should run, link against the new libraries, and say
# which version it is.
check() {
    msg "Checking the core tools"
    bash --version | head -n1
    perl -e 'printf "perl %vd\n", $^V'
    python3 -c 'import ssl, sys; print("Python", sys.version.split()[0], "with", ssl.OPENSSL_VERSION)'
    python3 -c 'import jinja2; print("Jinja2", jinja2.__version__)'
    openssl version
    echo "meson $(meson --version), ninja $(ninja --version)"
    kmod --version | head -n1
    cp --version | head -n1
    ip -V
    mke2fs -V 2>&1 | head -n1
    # OpenSSL must work end to end, not only load
    [[ $(printf yurei | openssl dgst -sha256 -r | cut -d' ' -f1) == \
        "$(printf yurei | sha256sum | cut -d' ' -f1)" ]] || { echo "openssl gives the wrong sum" >&2; exit 1; }
    # every program and library must find all the libraries it needs
    local missing
    missing=$(find /usr/bin /usr/sbin /usr/lib -maxdepth 1 -type f -perm -u+x -exec ldd {} + 2>/dev/null |
        grep 'not found' | sort -u || true)
    [[ -z $missing ]] || { echo "missing libraries:"$'\n'"$missing" >&2; exit 1; }
    echo "core tools OK"
}

STEPS=(ncurses_ sed_ psmisc_ gettext_ bison_ grep_ bash_ libtool_ gdbm gperf_ expat less_
       perl_ autoconf_ automake_ openssl_ elfutils libffi python_ flit_core packaging wheel_ setuptools
       markupsafe jinja2 ninja_ meson_ kmod_ coreutils_ diffutils_ gawk_ findutils_ gzip_
       iproute2_ kbd_ make_ patch_ tar_ texinfo_ e2fsprogs_ check)
run_steps "$@"
