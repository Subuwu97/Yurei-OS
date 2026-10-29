# Shared by the bootstrap steps: settings and helpers. Source it, don't run it.
# shellcheck shell=bash

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export YUREI=${YUREI:?set YUREI to the directory to build into}
sources=${SOURCES:?set SOURCES to the directory fetch.sh downloaded into}
export YUREI_TGT=x86_64-yurei-linux-gnu
export LC_ALL=POSIX
export PATH=$YUREI/tools/bin:$PATH
export CONFIG_SITE=$YUREI/usr/share/config.site
jobs=${JOBS:-$(nproc)}
build=${BUILD_DIR:-$YUREI/build}

version() { awk -v n="$1" '$1 == n {print $2}' "$here/sources.lock"; }
export GCC_VERSION GLIBC_VERSION
GCC_VERSION=$(version gcc)
GLIBC_VERSION=$(version glibc)

msg() { printf '\n\e[1;35m==>\e[0m \e[1m%s\e[0m\n' "$*"; }

# unpack NAME: a fresh source tree for NAME in $build, prints its path
unpack() {
    local tarball
    tarball=$(ls "$sources/$1-$(version "$1")".tar.*)
    rm -rf "${build:?}/$1-$(version "$1")"
    tar -xf "$tarball" -C "$build"
    echo "$build/$1-$(version "$1")"
}


# run_steps [STEP...]: runs the named steps of $STEPS (all by default), each
# in a subshell from a clean directory, with timings
run_steps() {
    local steps=("${@:-${STEPS[@]}}") step start
    mkdir -p "$build"
    for step in "${steps[@]}"; do
        [[ " ${STEPS[*]} " == *" $step "* ]] || { echo "unknown step: $step" >&2; exit 2; }
        start=$SECONDS
        (cd "$build" && "$step")
        printf '   (%s took %d s)\n' "$step" $((SECONDS - start))
    done
}

# cross_build NAME [CONFIGURE ARGS...]: the usual cross build of a
# temporary tool into $YUREI: configure for the target, make, install
cross_build() {
    local name=$1 src
    shift
    msg "$name $(version "$name")"
    src=$(unpack "$name")
    cd "$src" || return
    ./configure --prefix=/usr --host="$YUREI_TGT" --build="$(build_triplet)" "$@"
    make -j"$jobs"
    make DESTDIR="$YUREI" install
}

# the host's triplet, from the source tree's config.guess wherever it lives
build_triplet() {
    local guess
    for guess in build-aux/config.guess support/config.guess config.guess; do
        [[ -x $guess ]] && { "./$guess"; return; }
    done
    gcc -dumpmachine
}
