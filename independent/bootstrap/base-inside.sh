#!/bin/bash
# sed scripts below edit Makefiles, whose $(VARS) must stay literal
# shellcheck disable=SC2016
# Stage 2a, part 1: the final toolchain and core libraries, built inside the
# Yūrei chroot (started by `chroot.sh base-inside.sh`, after the chroot
# step). These replace the temporary versions: glibc, compression libraries,
# readline, binutils, GCC's maths libraries, ACLs and capabilities, password
# hashing and accounts (shadow), and finally GCC itself.
#
# Follows Linux From Scratch's chapter 8. Test suites are left out for now
# to keep CI runs short; the check at the end tests the new toolchain.
set -euo pipefail

# shellcheck source=independent/bootstrap/inside-lib.sh
source /bootstrap/inside-lib.sh

glibc_() {
    msg "glibc $(version glibc), final"
    local src
    src=$(unpack glibc)
    mkdir "$src/build" && cd "$src/build"
    echo "rootsbindir=/usr/sbin" > configparms
    ../configure --prefix=/usr --disable-werror --disable-nscd \
        libc_cv_slibdir=/usr/lib --enable-stack-protector=strong --enable-kernel=5.4
    make
    touch /etc/ld.so.conf
    # its install check runs the test suite we skipped
    sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
    make install
    sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd
    mkdir -p /usr/lib/locale
    localedef -i C -f UTF-8 C.UTF-8
    localedef -i en_US -f UTF-8 en_US.UTF-8
    cat > /etc/nsswitch.conf <<'NSS'
passwd: files
group: files
shadow: files
hosts: files dns
networks: files
protocols: files
services: files
ethers: files
rpc: files
NSS
    cat > /etc/ld.so.conf <<'LD'
/usr/local/lib
include /etc/ld.so.conf.d/*.conf
LD
    mkdir -p /etc/ld.so.conf.d
}

zlib() {
    build_simple zlib
    rm -f /usr/lib/libz.a
}

bzip2() {
    msg "bzip2 $(version bzip2)"
    local src
    src=$(unpack bzip2)
    cd "$src"
    # relative symlinks, and man pages in /usr/share/man
    sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
    sed -i 's@(PREFIX)/man@(PREFIX)/share/man@g' Makefile
    make -f Makefile-libbz2_so
    make clean
    make
    make PREFIX=/usr install
    cp -a libbz2.so.* /usr/lib
    ln -sf "libbz2.so.$(version bzip2)" /usr/lib/libbz2.so
    cp bzip2-shared /usr/bin/bzip2
    ln -sf bzip2 /usr/bin/bzcat
    ln -sf bzip2 /usr/bin/bunzip2
    rm -f /usr/lib/libbz2.a
}

xz() { build_simple xz --disable-static --docdir="/usr/share/doc/xz-$(version xz)"; }

lz4() {
    msg "lz4 $(version lz4)"
    local src
    src=$(unpack lz4)
    cd "$src"
    make BUILD_STATIC=no PREFIX=/usr
    make BUILD_STATIC=no PREFIX=/usr install
}

zstd() {
    msg "zstd $(version zstd)"
    local src
    src=$(unpack zstd)
    cd "$src"
    make prefix=/usr
    make prefix=/usr install
    rm -f /usr/lib/libzstd.a
}

file_() { build_simple file; }

readline() {
    msg "readline $(version readline)"
    local src
    src=$(unpack readline)
    cd "$src"
    # don't keep .old copies on reinstall, and no hard-coded library paths
    sed -i '/MV.*old/d' Makefile.in
    sed -i '/{OLDSUFF}/c:' support/shlib-install
    sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
    ./configure --prefix=/usr --disable-static --with-curses \
        --docdir="/usr/share/doc/readline-$(version readline)"
    make SHLIB_LIBS="-lncursesw"
    make install
}

m4_() { build_simple m4; }

bc() {
    msg "bc $(version bc)"
    local src
    src=$(unpack bc)
    cd "$src"
    CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r
    make
    make install
}

flex() {
    build_simple flex --docdir="/usr/share/doc/flex-$(version flex)" --disable-static
    ln -sf flex /usr/bin/lex
}

pkgconf() {
    build_simple pkgconf --disable-static
    ln -sf pkgconf /usr/bin/pkg-config
}

binutils_() {
    msg "binutils $(version binutils), final"
    local src
    src=$(unpack binutils)
    mkdir "$src/build" && cd "$src/build"
    ../configure --prefix=/usr --sysconfdir=/etc --enable-ld=default --enable-plugins \
        --enable-shared --disable-werror --enable-64-bit-bfd --enable-new-dtags \
        --with-system-zlib --enable-default-hash-style=gnu
    make tooldir=/usr
    make tooldir=/usr install
    rm -f /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a
}

gmp() {
    msg "gmp $(version gmp)"
    local src
    src=$(unpack gmp)
    cd "$src"
    # GCC 15 (C23) rejects an old-style declaration in one configure check
    sed -i '/long long t1;/,+1s/()/(...)/' configure
    # --host=none-linux-gnu: generic code that runs on any x86-64 CPU,
    # not tuned for the build machine's
    ./configure --prefix=/usr --enable-cxx --disable-static \
        --docdir="/usr/share/doc/gmp-$(version gmp)" --host=none-linux-gnu
    make
    make install
}

mpfr() { build_simple mpfr --disable-static --enable-thread-safe --docdir="/usr/share/doc/mpfr-$(version mpfr)"; }
mpc() { build_simple mpc --disable-static --docdir="/usr/share/doc/mpc-$(version mpc)"; }
attr() { build_simple attr --disable-static --sysconfdir=/etc --docdir="/usr/share/doc/attr-$(version attr)"; }
acl() { build_simple acl --disable-static --docdir="/usr/share/doc/acl-$(version acl)"; }

libcap() {
    msg "libcap $(version libcap)"
    local src
    src=$(unpack libcap)
    cd "$src"
    sed -i '/install -m.*STA/d' libcap/Makefile  # no static library
    make prefix=/usr lib=lib
    make prefix=/usr lib=lib install
}

libxcrypt() {
    build_simple libxcrypt --enable-hashes=strong,glibc --enable-obsolete-api=no \
        --disable-static --disable-failure-tokens
}

shadow() {
    msg "shadow $(version shadow)"
    local src
    src=$(unpack shadow)
    cd "$src"
    # coreutils provides groups; strong password hashing; mail in /var/mail
    sed -i 's/groups$(EXEEXT) //' src/Makefile.in
    find man -name Makefile.in -exec sed -i 's/groups\.1 / /' {} +
    sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
        -e 's:/var/spool/mail:/var/mail:' \
        -e '/PATH=/{s@/sbin:@@;s@/bin:@@}' -i etc/login.defs
    touch /usr/bin/passwd
    ./configure --sysconfdir=/etc --disable-static --with-bcrypt --with-yescrypt \
        --without-libbsd --with-group-name-max-length=32
    make
    make exec_prefix=/usr install
    pwconv
    grpconv
    mkdir -p /etc/default
    useradd -D --gid 999
}

gcc_() {
    msg "GCC $(version gcc), final"
    local src
    src=$(unpack gcc)
    sed -e '/m64=/s/lib64/lib/' -i.orig "$src/gcc/config/i386/t-linux64"
    mkdir "$src/build" && cd "$src/build"
    # 64-bit only for now; Steam's 32-bit libraries need a multilib GCC,
    # which comes with the gaming stage
    ../configure --prefix=/usr LD=ld --enable-languages=c,c++ \
        --enable-default-pie --enable-default-ssp --enable-host-pie \
        --disable-multilib --disable-bootstrap --disable-fixincludes --with-system-zlib
    make
    make install
    local target version
    target=$(gcc -dumpmachine)
    version=$(version gcc)
    chown -R root:root "/usr/lib/gcc/$target/$version/include"
    ln -sfr /usr/bin/cpp /usr/lib
    mkdir -p /usr/lib/bfd-plugins
    ln -sf "../../libexec/gcc/$target/$version/liblto_plugin.so" /usr/lib/bfd-plugins/
}

# The final toolchain must link against the final glibc, use the right
# loader and find its headers and start files in /usr.
check() {
    msg "Checking the final toolchain"
    local dir
    dir=$(mktemp -d)
    cd "$dir"
    echo 'int main(void) { return 0; }' | cc -x c - -v -Wl,--verbose > dummy.log 2>&1
    readelf -l a.out | grep -q 'Requesting program interpreter: /lib64/ld-linux-x86-64.so.2' ||
        { echo "wrong program interpreter" >&2; exit 1; }
    # GCC reaches /usr/lib through its own directory (…/gcc/<target>/<ver>/../../../../lib),
    # so match any path into /usr/lib, as Linux From Scratch's check does
    grep -Eq '/usr/lib.*/S?crt[1in].*succeeded' dummy.log || { echo "start files not from /usr/lib" >&2; exit 1; }
    grep -Eq 'attempt to open /usr/lib.*/libc\.so\.6 succeeded' dummy.log ||
        { echo "not linked against /usr/lib/libc.so.6" >&2; exit 1; }
    grep -E '/usr/lib.*/S?crt[1in].*succeeded|libc\.so\.6 succeeded' dummy.log
    printf '#include <zlib.h>\n#include <stdio.h>\nint main(void){ printf("zlib %%s, built by Yūrei\\n", zlibVersion()); return 0; }\n' > z.c
    gcc z.c -lz -o z && ./z
    gcc --version | head -n1
    ld --version | head -n1
    ldd --version | head -n1
    cd / && rm -rf "$dir"
    echo "base toolchain OK"
}

STEPS=(glibc_ zlib bzip2 xz lz4 zstd file_ readline m4_ bc flex pkgconf binutils_
       gmp mpfr mpc attr acl libcap libxcrypt shadow gcc_ check)
run_steps "$@"
