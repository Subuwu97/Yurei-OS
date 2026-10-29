#!/bin/bash
# Stage 2b: pacman, Yūrei's package manager, built inside the Yūrei chroot
# (started by `chroot.sh pacman-inside.sh`, after stage 2a) with what it
# needs: GnuPG and its libraries to sign and check packages, libarchive for
# the package files, curl to download them, and fakeroot for makepkg.
#
# The check then does what Yūrei's package repository will do: builds a
# package with makepkg as an ordinary user, signs it, puts it in a signed
# repository and installs it with pacman, trusting only Yūrei's key; and it
# makes sure pacman refuses an unsigned package.
set -euo pipefail

# shellcheck source=independent/bootstrap/inside-lib.sh
source /bootstrap/inside-lib.sh

# --- GnuPG ---------------------------------------------------------------

libgpg_error() { build_simple libgpg-error; }
libgcrypt() { build_simple libgcrypt; }
libassuan() { build_simple libassuan; }
libksba() { build_simple libksba; }
npth() { build_simple npth; }

gnupg() {
    # no LDAP or TLS key servers and no SQLite (TOFU) yet: signing and
    # checking signatures is what's needed
    build_simple gnupg --disable-ldap --disable-gnutls --disable-ntbtls --disable-sqlite \
        --docdir="/usr/share/doc/gnupg-$(version gnupg)"
}

gpgme() {
    # only the C library (and its Lisp files): pacman needs nothing else
    build_simple gpgme --disable-static --disable-gpg-test --disable-gpgsm-test \
        --enable-languages=cl
}

# --- package files and downloads -----------------------------------------

libarchive() { build_simple libarchive --disable-static --without-xml2; }

curl_() {
    # certificates come with Yūrei's CA bundle later; the path is set now
    build_simple curl --disable-static --with-openssl --without-libpsl \
        --enable-threaded-resolver --with-ca-path=/etc/ssl/certs
}

fakeroot_() {
    local src
    msg "fakeroot $(version fakeroot)"
    # fakeroot's own upstream is Debian, which publishes its releases as
    # fakeroot_<version>.orig.tar.gz
    rm -rf "$build/fakeroot-$(version fakeroot)"
    tar -xf "/sources/fakeroot_$(version fakeroot).orig.tar.gz" -C "$build"
    src=$build/fakeroot-$(version fakeroot)
    cd "$src"
    ./configure --prefix=/usr --libdir=/usr/lib/libfakeroot --disable-static --with-ipc=sysv
    # translated manual pages need po4a, which Yūrei doesn't have yet
    command -v po4a >/dev/null || printf 'all:\ninstall:\n' > doc/Makefile
    make
    make install
    install -d /etc/ld.so.conf.d
    echo /usr/lib/libfakeroot > /etc/ld.so.conf.d/fakeroot.conf
    ldconfig
}

# --- pacman --------------------------------------------------------------

pacman_() {
    local src
    msg "pacman $(version pacman)"
    src=$(unpack pacman)
    mkdir "$src/build" && cd "$src/build"
    # manual pages need asciidoc, which Yūrei doesn't have yet
    meson setup .. --prefix=/usr --sysconfdir=/etc --localstatedir=/var --buildtype=release \
        -D doc=disabled -D scriptlet-shell=/usr/bin/bash -D ldconfig=/usr/sbin/ldconfig \
        -D crypto=openssl -D gpgme=enabled
    ninja
    ninja install
    # pacman's database and package cache
    install -d /var/lib/pacman/local /var/cache/pacman/pkg
    # Yūrei's packages are compressed with zstd (makepkg's own default is gzip)
    sed -i -e "s/^PKGEXT=.*/PKGEXT='.pkg.tar.zst'/" -e "s/^SRCEXT=.*/SRCEXT='.src.tar.zst'/" /etc/makepkg.conf
    grep -qx "PKGEXT='.pkg.tar.zst'" /etc/makepkg.conf
    # the users pacman's units and download sandbox run as
    systemd-sysusers
}

# Runs a command as an ordinary user; makepkg won't run as root.
as_user() {
    local user=$1
    shift
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

check() {
    msg "Checking pacman: build, sign, publish, install"
    pacman --version | grep -m1 'Pacman v'
    makepkg --version | head -n1
    gpg --version | head -n1
    curl --version | head -n1
    bsdtar --version
    fakeroot --version

    local user=yurei-test-builder home test=/tmp/pacman-test fpr
    userdel -r "$user" 2>/dev/null || true
    rm -rf "$test"
    useradd -m "$user"
    home=$(getent passwd "$user" | cut -d: -f6)

    # a throwaway signing key, as Yūrei's packager key will be
    as_user "$user" gpg --batch --quiet --passphrase '' \
        --quick-gen-key "Yūrei test packager <test@yurei.invalid>" ed25519 sign never
    fpr=$(as_user "$user" gpg --batch --with-colons --list-keys | awk -F: '/^fpr/ {print $10; exit}')

    # a tiny package, the way every Yūrei package will be made
    as_user "$user" mkdir -p hello repo
    cat > "$home/hello/PKGBUILD" <<'PKG'
pkgname=yurei-hello
pkgver=1.0
pkgrel=1
pkgdesc="Says hello from a Yūrei package"
arch=(x86_64)
license=(MIT)
options=(!debug !lto)

build() {
    printf '#include <stdio.h>\nint main(void) { puts("Hello from a signed Yūrei package"); return 0; }\n' > hello.c
    cc $CFLAGS $LDFLAGS -o yurei-hello hello.c
}

package() {
    install -Dm755 yurei-hello "$pkgdir/usr/bin/yurei-hello"
}
PKG
    chown "$user:" "$home/hello/PKGBUILD"
    as_user "$user" sh -c "cd hello && PKGDEST=\$HOME/repo makepkg --sign --key $fpr --noconfirm"
    as_user "$user" sh -c "cd repo && repo-add --sign --key $fpr --verify yurei-test.db.tar.zst yurei-hello-1.0-1-x86_64.pkg.tar.zst"
    ls -l "$home/repo"

    # pacman in a separate root, trusting only that key
    mkdir -p "$test"/{root/var/lib/pacman,cache,gnupg}
    cat > "$test/pacman.conf" <<CONF
[options]
Architecture = auto
SigLevel = Required DatabaseRequired
LocalFileSigLevel = Required
CacheDir = $test/cache
GPGDir = $test/gnupg

[yurei-test]
Server = file://$home/repo
CONF
    as_user "$user" gpg --batch --armor --export "$fpr" > "$test/key.asc"
    pacman-key --config "$test/pacman.conf" --gpgdir "$test/gnupg" --init
    pacman-key --config "$test/pacman.conf" --gpgdir "$test/gnupg" --add "$test/key.asc"
    pacman-key --config "$test/pacman.conf" --gpgdir "$test/gnupg" --lsign-key "$fpr"
    local p=(pacman --config "$test/pacman.conf" --root "$test/root" --dbpath "$test/root/var/lib/pacman"
             --gpgdir "$test/gnupg" --noconfirm)
    "${p[@]}" -Sy yurei-hello
    "${p[@]}" -Q yurei-hello
    "$test/root/usr/bin/yurei-hello"

    # an unsigned package must be refused
    rm -f "$home/repo/yurei-hello-1.0-1-x86_64.pkg.tar.zst.sig"
    if "${p[@]}" -U "$home/repo/yurei-hello-1.0-1-x86_64.pkg.tar.zst" 2>/dev/null; then
        echo "pacman installed an unsigned package" >&2
        exit 1
    fi
    echo "unsigned package refused, as it should be"
    "${p[@]}" -R yurei-hello
    [[ ! -e $test/root/usr/bin/yurei-hello ]]

    # leave nothing of the test behind in the system
    as_user "$user" gpgconf --kill all
    userdel -r "$user"
    rm -rf "$test"
    echo "pacman OK"
}

STEPS=(libgpg_error libgcrypt libassuan libksba npth gnupg gpgme libarchive curl_ fakeroot_ pacman_ check)
run_steps "$@"
