#!/usr/bin/env bash
# Build the Yūrei ISO.
#
# Yūrei layers its branding, packages and installer step on top of CachyOS's
# official live ISO profile (pinned in upstream.conf):
#   1. build the yurei-* packages from pkg/ into a local repository
#   2. fetch CachyOS-Live-ISO at the pinned commit
#   3. apply overlay/ (files, package list changes, branding, installer hook)
#   4. run CachyOS's buildiso.sh and collect the ISO into out/
#
# Run as a normal user on CachyOS or Arch with: archiso mkinitcpio-archiso
# git squashfs-tools grub base-devel. Building the ISO itself uses sudo.
#
#   ./build.sh                 full build
#   ./build.sh --prepare-only  stop after step 3 (used by CI)
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=upstream.conf
source "$here/upstream.conf"

work=${WORK_DIR:-$here/work}
out=${OUT_DIR:-$here/out}
prepare_only=false

msg() { printf '\e[1;35m==>\e[0m \e[1m%s\e[0m\n' "$*"; }
die() { printf '\e[1;31merror:\e[0m %s\n' "$*" >&2; exit 1; }

check_host() {
    [[ $EUID -ne 0 ]] || die "run as a normal user (makepkg refuses root); sudo is used where needed"
    local tool
    for tool in git makepkg repo-add; do
        command -v "$tool" >/dev/null || die "missing $tool - install base-devel and git"
    done
    if ! $prepare_only; then
        command -v mkarchiso >/dev/null || die "missing mkarchiso - install archiso mkinitcpio-archiso"
        grep -q '^\[cachyos' /etc/pacman.conf ||
            die "building the ISO needs the CachyOS repositories on this machine (run it on CachyOS)"
    fi
}

build_packages() {
    msg "Building yurei packages"
    rm -rf "$work/packages"
    mkdir -p "$work/packages"
    (cd "$here/pkg/yurei-settings" && PKGDEST="$work/packages" makepkg --force --cleanbuild --nodeps)
    repo-add --quiet "$work/packages/yurei.db.tar.gz" "$work/packages"/*.pkg.tar.zst
}

fetch_upstream() {
    msg "Fetching CachyOS-Live-ISO @ ${UPSTREAM_REF:0:12}"
    local dir=$work/upstream
    if [[ -d $dir/.git ]]; then
        git -C "$dir" fetch --quiet origin
    else
        git clone --quiet "$UPSTREAM_URL" "$dir"
    fi
    git -C "$dir" checkout --quiet --force --detach "$UPSTREAM_REF"
    # throw away the previous build's overlay and outputs
    sudo_if_needed git -C "$dir" clean --quiet -fdx
}

# The previous ISO build leaves root-owned files behind.
sudo_if_needed() {
    if "$@" 2>/dev/null; then return; fi
    sudo "$@"
}

# Replace text in a file and fail loudly if the text wasn't there, so an
# upstream change can't silently drop part of the overlay.
replace() {
    local file=$1 from=$2 to=$3
    grep -qF -- "$from" "$file" || die "${file#"$work"/}: expected to find '$from' (upstream changed?)"
    FROM=$from TO=$to perl -0pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/g' "$file"
}

apply_overlay() {
    msg "Applying Yūrei overlay"
    local iso=$work/upstream/archiso

    cp -a "$here/overlay/airootfs/." "$iso/airootfs/"
    install -d "$iso/airootfs/opt/yurei/packages"
    cp "$work/packages"/*.pkg.tar.zst "$iso/airootfs/opt/yurei/packages/"
    # signing key for the [yurei] update repository, once one exists
    if [[ -f $here/keys/yurei.asc ]]; then
        cp "$here/keys/yurei.asc" "$iso/airootfs/opt/yurei/yurei.asc"
    fi

    # package list
    local list=$iso/packages_desktop.x86_64 tmp
    tmp=$(mktemp)
    grep -vxF -f <(grep -v '^#' "$here/overlay/packages.remove" | sed '/^$/d'; echo '#none#') "$list" > "$tmp"
    grep -v '^#' "$here/overlay/packages.add" | sed '/^$/d' >> "$tmp"
    sort -u "$tmp" > "$list"
    rm -f "$tmp"

    # local repository with the yurei-* packages, for building the live system
    cat >> "$iso/pacman.conf" <<EOF

[yurei]
SigLevel = Optional TrustAll
Server = file://$work/packages
EOF

    # ISO metadata; iso_name stays "cachyos" because buildiso.sh expects it,
    # and the ISO is renamed once built
    local profile=$iso/profiledef.sh
    # shellcheck disable=SC2016 # $(date ...) is meant for profiledef.sh to expand
    sed -i \
        -e 's|^iso_label=.*|iso_label="YUREI_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"|' \
        -e 's|^iso_publisher=.*|iso_publisher="Yūrei Linux <https://github.com/subuwu97/Y-rei-Linux>"|' \
        -e 's|^iso_application=.*|iso_application="Yūrei Linux Live/Install"|' \
        "$profile"
    # mkarchiso doesn't keep file modes from airootfs
    cat >> "$profile" <<'EOF'
file_permissions+=(
  ["/usr/local/bin/yurei-install-target"]="0:0:755"
  ["/usr/local/bin/yurei-calamares-patch"]="0:0:755"
)
EOF

    # boot menus (plain ASCII: the BIOS menu can't draw "ū")
    [[ -f $iso/grub/splash.png && -f $iso/syslinux/splash.png ]] ||
        die "upstream boot splash images moved (upstream changed?)"
    cp "$here/overlay/boot/splash.png" "$iso/grub/splash.png"
    cp "$here/overlay/boot/splash.png" "$iso/syslinux/splash.png"
    local f
    for f in "$iso"/grub/*.cfg "$iso"/syslinux/*.cfg "$iso"/efiboot/loader/entries/*.conf; do
        sed -i 's/CachyOS/Yurei/g' "$f"
    done

    # hook Yūrei's install step into the installer
    replace "$iso/airootfs/usr/local/bin/calamares-online.sh" \
        '    exec pkexec-wrapper calamares' \
        $'    sudo /usr/local/bin/yurei-calamares-patch /etc/calamares/settings.conf\n    exec pkexec-wrapper calamares'
}

build_iso() {
    msg "Building the ISO (this takes a while)"
    (cd "$work/upstream" && sudo ./buildiso.sh -p desktop -w)

    local iso
    iso=$(find "$work/upstream/out/desktop" -maxdepth 1 -name '*.iso' -print -quit)
    [[ -n $iso ]] || die "buildiso.sh finished but produced no ISO"
    mkdir -p "$out"
    local name
    name="yurei-$(date +%Y.%m.%d)-x86_64.iso"
    sudo mv "$iso" "$out/$name"
    sudo chown "$(id -u):$(id -g)" "$out/$name"
    (cd "$out" && sha256sum "$name" > "$name.sha256")
    msg "Done: $out/$name"
}

main() {
    [[ ${1:-} == "--prepare-only" ]] && prepare_only=true
    check_host
    build_packages
    fetch_upstream
    apply_overlay
    if $prepare_only; then
        msg "Profile prepared in $work/upstream/archiso"
    else
        build_iso
    fi
}

# tests source this file to exercise apply_overlay on its own
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
