# Helpers for the scripts that run inside the new Yūrei system (started by
# chroot.sh). Source it, don't run it.
# shellcheck shell=bash

build=/build
mkdir -p "$build"

version() { awk -v n="$1" '$1 == n {print $2}' /bootstrap/sources.lock; }
msg() { printf '\n\e[1;35m==>\e[0m \e[1m%s\e[0m\n' "$*"; }
unpack() {
    local tarball
    tarball=$(ls "/sources/$1-$(version "$1")".tar.*)
    rm -rf "${build:?}/$1-$(version "$1")"
    tar -xf "$tarball" -C "$build"
    echo "$build/$1-$(version "$1")"
}

# run_steps [STEP...]: runs the named steps of $STEPS (all by default), with timings
run_steps() {
    local steps=("${@:-${STEPS[@]}}") step start
    for step in "${steps[@]}"; do
        [[ " ${STEPS[*]} " == *" $step "* ]] || { echo "unknown step: $step" >&2; exit 2; }
        start=$SECONDS
        (cd "$build" 2>/dev/null || cd /; "$step")
        printf '   (%s took %d s)\n' "$step" $((SECONDS - start))
    done
}

# build_simple NAME [CONFIGURE ARGS...]: configure --prefix=/usr, make, install
build_simple() {
    local name=$1 src
    shift
    msg "$name $(version "$name")"
    src=$(unpack "$name")
    cd "$src" || return
    ./configure --prefix=/usr "$@"
    make
    make install
}
