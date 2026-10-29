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
set -euo pipefail

# shellcheck source=independent/bootstrap/inside-lib.sh
source /bootstrap/inside-lib.sh

srv=/srv/yurei
recipes=$srv/recipes
repo=$srv/repo
user=yurei-builder

# Runs a command as the build user; makepkg won't run as root.
as_user() {
    python3 -c '
import os, pwd, sys
p = pwd.getpwnam(sys.argv[1])
os.setgroups([])
os.setgid(p.pw_gid)
os.setuid(p.pw_uid)
os.environ.update(HOME=p.pw_dir, USER=p.pw_name, LOGNAME=p.pw_name)
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
    rm -rf "$repo"
    install -d -o "$user" "$repo"
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

# Builds every recipe in ORDER. --nodeps: while bootstrapping, everything a
# recipe needs is in this system already, but not yet known to pacman.
packages() {
    local name fpr start
    fpr=$(fingerprint)
    while read -r name; do
        [[ -z $name || $name == \#* ]] && continue
        msg "$name"
        start=$SECONDS
        rm -rf "$(home)/build/$name"
        as_user mkdir -p build
        cp -r "$recipes/$name" "$(home)/build/"
        chown -R "$user:" "$(home)/build/$name"
        as_user sh -c "cd build/$name && MAKEPKG_CONF=$srv/makepkg.conf SRCDEST=/sources \
            PKGDEST=$repo makepkg --nodeps --sign --key $fpr --noconfirm --noprogressbar"
        rm -rf "$(home)/build/$name"
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
    "${p[@]}" -Sy bash
    echo "installed:"
    "${p[@]}" -Q
    # inside the new system, with only what pacman put there
    # shellcheck disable=SC2016 # expanded by the new system's bash
    chroot "$root" /usr/bin/bash -c '. /etc/os-release
        echo "Bash $BASH_VERSION running in $PRETTY_NAME, installed by pacman"
        ldd /usr/bin/bash'
    gpgconf --homedir "$gnupg" --kill all
    as_user gpgconf --kill all
    rm -rf "$root" "$gnupg" "$srv/cache" "$srv/pacman.conf"
    echo "repository OK"
}

cleanup() {
    as_user gpgconf --kill all 2>/dev/null || true
    userdel -r "$user"
}

STEPS=(setup packages publish check cleanup)
run_steps "$@"
