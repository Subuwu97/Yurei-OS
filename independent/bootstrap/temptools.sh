#!/usr/bin/env bash
# Temporary tools: the second bootstrap step, after stage1.sh.
#
# Uses the cross toolchain from stage1.sh to build, for Yūrei, the basic
# programs a build needs (a shell, coreutils, make, sed, tar and so on),
# then binutils and GCC again, this time as programs that run on Yūrei. The
# result in $YUREI is a small system that can build software with no help
# from the host: the next step enters it with chroot and builds the rest
# from inside. Like stage1.sh, this follows Linux From Scratch's method and
# runs as an ordinary user.
#
#   YUREI=/path/to/root SOURCES=/path/to/sources ./temptools.sh [STEP...]
set -euo pipefail

# shellcheck source=independent/bootstrap/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ -x $YUREI/tools/bin/$YUREI_TGT-gcc ]] || { echo "run stage1.sh first" >&2; exit 1; }

m4() { cross_build m4; }

ncurses() {
    msg "ncurses $(version ncurses)"
    local src
    src=$(unpack ncurses)
    cd "$src"
    # No C++ binding: the temporary tools don't need it, and ncurses 6.5's
    # configure can't detect C++'s bool when cross-compiling with GCC 15
    # (C23), so the binding fails to compile. The final ncurses has it.
    # tic has to run on the host while building, so build one for it first
    mkdir build
    (cd build && ../configure AWK=gawk && make -C include && make -C progs tic)
    ./configure --prefix=/usr --host="$YUREI_TGT" --build="$(./config.guess)" \
        --mandir=/usr/share/man --with-manpage-format=normal --with-shared \
        --without-normal --without-cxx-binding --without-debug --without-ada \
        --disable-stripping AWK=gawk
    make -j"$jobs"
    make DESTDIR="$YUREI" TIC_PATH="$(pwd)/build/progs/tic" install
    ln -sf libncursesw.so "$YUREI/usr/lib/libncurses.so"
    # programs asking for the wide-character API get it without a define
    sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$YUREI/usr/include/curses.h"
}

bash_() {
    cross_build bash --without-bash-malloc
    ln -sf bash "$YUREI/usr/bin/sh"
}

coreutils() {
    cross_build coreutils --enable-install-program=hostname --enable-no-install-program=kill,uptime
    mv "$YUREI/usr/bin/chroot" "$YUREI/usr/sbin/"
}

diffutils() { cross_build diffutils gl_cv_func_strcasecmp_works=y; }

file_() {
    msg "file $(version file)"
    local src
    src=$(unpack file)
    cd "$src"
    # building the magic database needs a file of the same version on the host
    mkdir build
    (cd build && ../configure --disable-bzlib --disable-libseccomp --disable-xzlib --disable-zlib && make -j"$jobs")
    ./configure --prefix=/usr --host="$YUREI_TGT" --build="$(./config.guess)"
    make -j"$jobs" FILE_COMPILE="$(pwd)/build/src/file"
    make DESTDIR="$YUREI" install
    rm -f "$YUREI/usr/lib/libmagic.la"
}

findutils() { cross_build findutils --localstatedir=/var/lib/locate; }

gawk_() {
    local src
    src=$(unpack gawk)
    sed -i 's/extras//' "$src/Makefile.in"  # unneeded extras
    # cross_build unpacks again; reuse this tree instead
    msg "gawk $(version gawk)"
    cd "$src"
    ./configure --prefix=/usr --host="$YUREI_TGT" --build="$(build_triplet)"
    make -j"$jobs"
    make DESTDIR="$YUREI" install
}

grep_() { cross_build grep; }
gzip_() { cross_build gzip; }
make_() { cross_build make; }
patch_() { cross_build patch; }
sed_() { cross_build sed; }
tar_() { cross_build tar; }

xz_() {
    cross_build xz --disable-static --docdir=/usr/share/doc/xz
    rm -f "$YUREI/usr/lib/liblzma.la"
}

binutils_pass2() {
    msg "binutils $(version binutils), pass 2 (runs on Yūrei)"
    local src
    src=$(unpack binutils)
    mkdir "$src/build" && cd "$src/build"
    ../configure --prefix=/usr --build="$(../config.guess)" --host="$YUREI_TGT" \
        --disable-nls --enable-shared --enable-gprofng=no --disable-werror \
        --enable-64-bit-bfd --enable-new-dtags --enable-default-hash-style=gnu
    make -j"$jobs"
    make DESTDIR="$YUREI" install
    rm -f "$YUREI"/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
}

gcc_pass2() {
    msg "GCC $GCC_VERSION, pass 2 (runs on Yūrei)"
    local src lib
    src=$(unpack gcc)
    for lib in gmp mpfr mpc; do
        mv "$(unpack "$lib")" "$src/$lib"
    done
    sed -e '/m64=/s/lib64/lib/' -i.orig "$src/gcc/config/i386/t-linux64"
    # build libgcc and libstdc++ with POSIX threads
    sed '/thread_header =/s/@.*@/gthr-posix.h/' -i "$src/libgcc/Makefile.in" "$src/libstdc++-v3/include/Makefile.in"
    mkdir "$src/build" && cd "$src/build"
    ../configure --build="$(../config.guess)" --host="$YUREI_TGT" --target="$YUREI_TGT" \
        LDFLAGS_FOR_TARGET="-L$PWD/$YUREI_TGT/libgcc" \
        --prefix=/usr --with-build-sysroot="$YUREI" \
        --enable-default-pie --enable-default-ssp \
        --disable-nls --disable-multilib --disable-libatomic --disable-libgomp \
        --disable-libquadmath --disable-libsanitizer --disable-libssp --disable-libvtv \
        --enable-languages=c,c++
    make -j"$jobs"
    make DESTDIR="$YUREI" install
    ln -sf gcc "$YUREI/usr/bin/cc"
}

# Every program installed for Yūrei must be built for it: ask for Yūrei's
# dynamic loader, and find its libraries only in Yūrei's own /usr/lib.
check() {
    msg "Checking the temporary tools"
    local prog interp missing=0
    for prog in bash sh ls cp make sed grep gawk tar xz gzip find diff patch file m4 gcc g++ ld as; do
        if [[ ! -e $YUREI/usr/bin/$prog ]]; then
            echo "missing: /usr/bin/$prog" >&2
            missing=1
            continue
        fi
    done
    (( missing == 0 )) || exit 1
    for prog in bash make gcc ld; do
        interp=$(readelf -l "$YUREI/usr/bin/$prog" | grep -o 'interpreter: [^]]*' | cut -d' ' -f2)
        [[ $interp == /lib64/ld-linux-x86-64.so.2 ]] ||
            { echo "/usr/bin/$prog asks for $interp" >&2; exit 1; }
    done
    # run Yūrei's own bash and gcc on Yūrei's own glibc, as the chroot will
    local loader=$YUREI/usr/lib/ld-linux-x86-64.so.2 libs=$YUREI/usr/lib
    # shellcheck disable=SC2016 # expanded by Yūrei's bash, not this one
    "$loader" --library-path "$libs" "$YUREI/usr/bin/bash" -c 'echo "bash $BASH_VERSION runs on Yūrei"'
    "$loader" --library-path "$libs" "$YUREI/usr/bin/gcc" --version | head -n1
    echo "temporary tools OK"
}

STEPS=(m4 ncurses bash_ coreutils diffutils file_ findutils gawk_ grep_ gzip_ make_ patch_ sed_ tar_ xz_
       binutils_pass2 gcc_pass2 check)
run_steps "$@"
