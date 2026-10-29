#!/usr/bin/env bash
# Stage 1: a cross toolchain for Yūrei, built from upstream source.
#
# Builds binutils, GCC (C and C++), the Linux API headers, glibc and
# libstdc++ for the target x86_64-yurei-linux-gnu into $YUREI. This is the
# first step of the bootstrap described in docs/INDEPENDENT.md. It follows
# the method of Linux From Scratch's cross toolchain chapter, so it runs on
# any Linux host with a C compiler, as an ordinary user. The host's own
# libraries never end up in the result.
#
# The result, $YUREI/tools plus a minimal $YUREI/usr, can compile programs
# for Yūrei. Stage 2 uses it to build the temporary tools for a chroot that
# no longer needs the host at all.
#
#   YUREI=/path/to/root SOURCES=/path/to/sources ./stage1.sh
set -euo pipefail

# shellcheck source=independent/bootstrap/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# the minimal directory layout: /bin, /lib and /sbin point into /usr
layout() {
    mkdir -p "$YUREI"/{etc,var,tools} "$YUREI"/usr/{bin,lib,sbin} "$YUREI/lib64" "$build"
    for dir in bin lib sbin; do
        [[ -e $YUREI/$dir ]] || ln -s "usr/$dir" "$YUREI/$dir"
    done
}

binutils_pass1() {
    msg "binutils $(version binutils), pass 1"
    local src
    src=$(unpack binutils)
    mkdir "$src/build" && cd "$src/build"
    ../configure --prefix="$YUREI/tools" --with-sysroot="$YUREI" --target="$YUREI_TGT" \
        --disable-nls --enable-gprofng=no --disable-werror \
        --enable-new-dtags --enable-default-hash-style=gnu
    make -j"$jobs"
    make install
}

gcc_pass1() {
    msg "GCC $GCC_VERSION, pass 1 (no C library yet)"
    local src lib
    src=$(unpack gcc)
    for lib in gmp mpfr mpc; do
        mv "$(unpack "$lib")" "$src/$lib"
    done
    # 64-bit libraries in lib, not lib64
    sed -e '/m64=/s/lib64/lib/' -i.orig "$src/gcc/config/i386/t-linux64"
    mkdir "$src/build" && cd "$src/build"
    ../configure --target="$YUREI_TGT" --prefix="$YUREI/tools" \
        --with-glibc-version="$GLIBC_VERSION" --with-sysroot="$YUREI" \
        --with-newlib --without-headers \
        --enable-default-pie --enable-default-ssp \
        --disable-nls --disable-shared --disable-multilib --disable-threads \
        --disable-libatomic --disable-libgomp --disable-libquadmath --disable-libssp \
        --disable-libvtv --disable-libstdcxx --enable-languages=c,c++
    make -j"$jobs"
    make install
    # the full limits.h, which the pass-1 build can't install by itself
    cd "$src"
    cat gcc/limitx.h gcc/glimits.h gcc/limity.h \
        > "$(dirname "$("$YUREI_TGT-gcc" -print-libgcc-file-name)")/include/limits.h"
}

linux_headers() {
    msg "Linux $(version linux) API headers"
    local src
    src=$(unpack linux)
    cd "$src"
    make mrproper
    make headers
    find usr/include -type f ! -name '*.h' -delete
    cp -r usr/include "$YUREI/usr"
}

glibc_build() {
    msg "glibc $GLIBC_VERSION"
    local src
    src=$(unpack glibc)
    ln -sf ../lib/ld-linux-x86-64.so.2 "$YUREI/lib64"
    ln -sf ../lib/ld-linux-x86-64.so.2 "$YUREI/lib64/ld-lsb-x86-64.so.3"
    mkdir "$src/build" && cd "$src/build"
    echo "rootsbindir=/usr/sbin" > configparms
    ../configure --prefix=/usr --host="$YUREI_TGT" --build="$(../scripts/config.guess)" \
        --enable-kernel=5.4 --with-headers="$YUREI/usr/include" \
        --disable-nscd libc_cv_slibdir=/usr/lib
    make -j"$jobs"
    make DESTDIR="$YUREI" install
    # ldd looks for the loader in /lib64, not /usr/lib64
    sed '/RTLDLIST=/s@/usr@@g' -i "$YUREI/usr/bin/ldd"
}

libstdcxx() {
    msg "libstdc++ from GCC $GCC_VERSION"
    local src
    src=$(unpack gcc)
    mkdir "$src/build" && cd "$src/build"
    ../libstdc++-v3/configure --host="$YUREI_TGT" --build="$(../config.guess)" \
        --prefix=/usr --disable-multilib --disable-nls --disable-libstdcxx-pch \
        --with-gxx-include-dir="/tools/$YUREI_TGT/include/c++/$GCC_VERSION"
    make -j"$jobs"
    make DESTDIR="$YUREI" install
    # libtool archives only cause trouble when cross-compiling
    rm -f "$YUREI"/usr/lib/lib{stdc++{,exp,fs},supc++}.la
}

# The toolchain works if it can compile C and C++ against the new glibc,
# and the programs ask for Yūrei's dynamic loader, not the host's.
check() {
    msg "Checking the toolchain"
    local dir
    dir=$(mktemp -d)
    printf '#include <stdio.h>\nint main(void) { puts("hello from yurei"); return 0; }\n' > "$dir/hello.c"
    printf '#include <iostream>\n#include <string>\nint main() { std::string s = "yurei"; std::cout << s << "\\n"; }\n' > "$dir/hello.cpp"
    "$YUREI_TGT-gcc" "$dir/hello.c" -o "$dir/hello"
    "$YUREI_TGT-g++" "$dir/hello.cpp" -o "$dir/hello-cpp"
    local interp
    interp=$(readelf -l "$dir/hello" | grep -o 'interpreter: [^]]*' | cut -d' ' -f2)
    [[ $interp == /lib64/ld-linux-x86-64.so.2 ]] ||
        { echo "unexpected program interpreter: $interp" >&2; exit 1; }
    readelf -d "$dir/hello-cpp" | grep -q 'libstdc++' ||
        { echo "the C++ program doesn't use libstdc++" >&2; exit 1; }
    # run them against Yūrei's own glibc, not the host's
    "$YUREI/usr/lib/ld-linux-x86-64.so.2" --library-path "$YUREI/usr/lib" "$dir/hello"
    "$YUREI/usr/lib/ld-linux-x86-64.so.2" --library-path "$YUREI/usr/lib" "$dir/hello-cpp"
    rm -rf "$dir"
    echo "toolchain OK: $("$YUREI_TGT-gcc" --version | head -n1)"
}

STEPS=(layout binutils_pass1 gcc_pass1 linux_headers glibc_build libstdcxx check)
run_steps "$@"
