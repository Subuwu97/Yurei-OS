#!/bin/bash
# Stage 2c: Yūrei's own packages. Inside the Yūrei chroot (started by
# `chroot.sh repo-inside.sh`, after stage 2b), builds every recipe in
# independent/packages (copied to /srv/yurei/recipes) with makepkg, in the
# order of their ORDER file, signs each package, and publishes them in a
# signed repository, [yurei], in /srv/yurei/repo.
#
# The check then installs a new system into an empty directory from that
# repository with pacman alone, trusting only the repository's key, and
# runs a shell inside it.
#
# Packages are signed with a throwaway key made for each run, until Yūrei's
# own signing key is set up (docs/INDEPENDENT.md).
#
# A recipe that hasn't changed since the last run isn't built again: the
# workflow hands in that run's packages (/srv/yurei/previous) with a hash of
# each recipe, and they're reused and signed with this run's key.
set -euo pipefail

# shellcheck source=independent/bootstrap/inside-lib.sh
source /bootstrap/inside-lib.sh

srv=/srv/yurei
recipes=$srv/recipes
repo=$srv/repo
previous=$srv/previous
stamps=$srv/stamps
user=yurei-builder

# Runs a command as the build user; makepkg won't run as root.
as_user() {
    python3 -c '
import os, pwd, sys
p = pwd.getpwnam(sys.argv[1])
os.setgroups([])
os.setgid(p.pw_gid)
os.setuid(p.pw_uid)
# UTF-8 (chroot.sh sets LC_ALL=POSIX), so the non-ASCII file names in
# some sources (GCC) unpack
os.environ.update(HOME=p.pw_dir, USER=p.pw_name, LOGNAME=p.pw_name, LANG="C.UTF-8", LC_ALL="C.UTF-8")
os.chdir(p.pw_dir)
os.execvp(sys.argv[2], sys.argv[2:])' "$user" "$@"
}

home() { getent passwd "$user" | cut -d: -f6; }
fingerprint() { as_user gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr/ {print $10; exit}'; }

setup() {
    msg "Build user, signing key and build settings"
    [[ -f $recipes/ORDER ]] || { echo "no recipes in $recipes" >&2; exit 1; }
    getent passwd "$user" >/dev/null || useradd -m "$user"
    as_user gpg --batch --quiet --passphrase '' \
        --quick-gen-key "Yūrei build (throwaway) <build@yurei.invalid>" ed25519 sign never
    # systemd's boot loader is built with pyelftools; a build tool only,
    # like the rest of this system, not part of any package
    python3 -c 'import elftools' 2>/dev/null ||
        pip3 install --no-index --no-build-isolation --no-deps \
            "/sources/pyelftools-$(version pyelftools).tar.gz"
    rm -rf "$repo" "$srv/sources" "$stamps"
    install -d -o "$user" "$repo" "$srv/sources"
    install -d "$stamps"
    # makepkg wants a download folder it can write to; /sources is mounted
    # read-only, so it gets one with links to the verified files
    ln -s /sources/* "$srv/sources/"
    # Yūrei's build settings, on top of pacman's defaults
    cat > "$srv/makepkg.conf" <<CONF
source /etc/makepkg.conf
CFLAGS="-march=x86-64 -mtune=generic -O2 -pipe"
CXXFLAGS="\$CFLAGS"
LDFLAGS="-Wl,-O1 -Wl,--sort-common -Wl,--as-needed"
MAKEFLAGS="-j$(nproc)"
OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug !lto)
BUILDENV=(!distcc color !ccache !check !sign)
PACKAGER="Yūrei build <build@yurei.invalid>"
PKGEXT='.pkg.tar.zst'
CONF
}

# The recipe's files and the build settings, as one hash.
recipe_hash() {
    { cd "$recipes/$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum
      cat "$srv/makepkg.conf"; } | sha256sum | cut -c1-64
}

# reuse NAME HASH: copies the last run's packages for NAME, if its recipe is
# unchanged, and signs them with this run's key
reuse() {
    local name=$1 hash=$2 file
    [[ -f $previous/stamps/$name.hash && $(< "$previous/stamps/$name.hash") == "$hash" ]] || return 1
    while read -r file; do
        [[ -f $previous/$file ]] || return 1
    done < "$previous/stamps/$name.files"
    while read -r file; do
        install -o "$user" -m 644 "$previous/$file" "$repo/$file"
        as_user gpg --batch --yes --detach-sign --no-armor -u "$(fingerprint)" "$repo/$file"
    done < "$previous/stamps/$name.files"
    cp "$previous/stamps/$name".{hash,files} "$stamps/"
}

# install_here NAME: installs NAME's packages into this build system, so
# the recipes after it can build with them. Only for what the bootstrap
# didn't already put here (ORDER's "#> install from here on" line);
# signatures aren't checked (they were made a moment ago, by this run),
# nor dependencies (--nodeps twice): the bootstrap's own files aren't
# known to pacman.
install_here() {
    local file files=()
    while read -r file; do files+=("$repo/$file"); done < "$stamps/$1.files"
    printf '[options]\nSigLevel = Never\nLocalFileSigLevel = Never\n' > "$srv/install-pacman.conf"
    pacman --config "$srv/install-pacman.conf" -U --noconfirm --nodeps --nodeps --overwrite '*' \
        --noprogressbar "${files[@]}" > /dev/null
    echo "   installed here, for the recipes after it"
}

# Builds every recipe in ORDER. --nodeps: while bootstrapping, everything a
# recipe needs is in this system already, but not yet known to pacman (from
# ORDER's "#> install from here on" line, each package is installed here
# once built, for the ones after it).
packages() {
    local name fpr start hash env install=
    fpr=$(fingerprint)
    # the public key, for the yurei-keyring recipe
    as_user gpg --batch --armor --export "$fpr" > "$srv/signing-key.asc"
    env="MAKEPKG_CONF=$srv/makepkg.conf SRCDEST=$srv/sources PKGDEST=$repo YUREI_SIGNING_PUBKEY=$srv/signing-key.asc"
    while read -r name; do
        [[ $name == "#> install from here on" ]] && install=1
        [[ -z $name || $name == \#* ]] && continue
        msg "$name"
        start=$SECONDS
        hash=$(recipe_hash "$name")
        # the keyring holds this run's key, so it's always made afresh
        if [[ $name != yurei-keyring ]] && reuse "$name" "$hash"; then
            echo "   unchanged since the last run: reused"
            [[ -z $install ]] || install_here "$name"
            continue
        fi
        rm -rf "$(home)/build/$name"
        as_user mkdir -p build
        cp -r "$recipes/$name" "$(home)/build/"
        chown -R "$user:" "$(home)/build/$name"
        as_user sh -c "cd build/$name && $env makepkg --nodeps --sign --key $fpr --noconfirm --noprogressbar"
        as_user sh -c "cd build/$name && $env makepkg --packagelist" | xargs -n1 basename > "$stamps/$name.files"
        echo "$hash" > "$stamps/$name.hash"
        rm -rf "$(home)/build/$name"
        [[ -z $install ]] || install_here "$name"
        printf '   (%s took %d s)\n' "$name" $((SECONDS - start))
    done < "$recipes/ORDER"
}

publish() {
    msg "The [yurei] repository"
    local fpr
    fpr=$(fingerprint)
    as_user sh -c "cd $repo && repo-add --sign --key $fpr --verify yurei.db.tar.zst *.pkg.tar.zst"
    as_user gpg --batch --armor --export "$fpr" > "$repo/yurei-build.asc"
    ls -l "$repo"
}

# A new Yūrei system, installed from the repository by pacman alone.
check() {
    msg "Installing a new system from [yurei] with pacman"
    local root=$srv/newroot gnupg=$srv/gnupg fpr
    fpr=$(fingerprint)
    rm -rf "$root" "$gnupg"
    mkdir -p "$root/var/lib/pacman" "$gnupg"
    cat > "$srv/pacman.conf" <<CONF
[options]
Architecture = auto
SigLevel = Required DatabaseRequired
CacheDir = $srv/cache

[yurei]
Server = file://$repo
CONF
    pacman-key --config "$srv/pacman.conf" --gpgdir "$gnupg" --init
    pacman-key --config "$srv/pacman.conf" --gpgdir "$gnupg" --add "$repo/yurei-build.asc"
    pacman-key --config "$srv/pacman.conf" --gpgdir "$gnupg" --lsign-key "$fpr"
    local p=(pacman --config "$srv/pacman.conf" --root "$root" --dbpath "$root/var/lib/pacman"
             --gpgdir "$gnupg" --noconfirm)
    # everything in the repository, so every package's dependencies are tested
    local all
    "${p[@]}" -Sy
    mapfile -t all < <("${p[@]}" -Slq yurei)
    "${p[@]}" -S "${all[@]}"
    echo "installed $("${p[@]}" -Qq | wc -l) packages"
    mount --bind /dev "$root/dev"
    mount -t proc proc "$root/proc"
    if ! chroot "$root" /usr/bin/bash -eu < /bootstrap/repo-check.sh; then
        umount "$root/proc" "$root/dev"
        exit 1
    fi
    umount "$root/proc" "$root/dev"
    gpgconf --homedir "$gnupg" --kill all
    as_user gpgconf --kill all
    rm -rf "$root" "$gnupg" "$srv/cache" "$srv/pacman.conf" "$srv/sources"
    echo "repository OK"
}

cleanup() {
    as_user gpgconf --kill all 2>/dev/null || true
    userdel -r "$user"
}

STEPS=(setup packages publish check cleanup)
run_steps "$@"
