# Runs inside a system installed from [yurei] by pacman alone (repo-inside.sh
# feeds it to that system's bash): its tools must work, and every program
# and library must find the libraries it needs, which shows that each
# recipe's dependencies are complete.
# shellcheck shell=bash
. /etc/os-release
echo "Bash $BASH_VERSION running in $PRETTY_NAME, installed by pacman"
cd /tmp || exit 1

# the compiler
printf '#include <stdio.h>\nint main(void) { puts("C works"); return 0; }\n' > c.c
printf '#include <iostream>\nint main() { std::cout << "C++ works" << std::endl; }\n' > cxx.cc
gcc -o c c.c && ./c
g++ -o cxx cxx.cc && ./cxx
gcc --version | head -n1

# the core tools
echo "hello yurei" | sed 's/hello/hi/' | grep -q "hi yurei"
printf '1 2\n3 4\n' | awk '{ s += $1 + $2 } END { exit s != 10 }'
mkdir -p t/a && echo data > t/a/f
tar czf t.tar.gz t && rm -r t && tar xzf t.tar.gz && diff -r t t && cmp t/a/f <(echo data)
[[ $(find t -type f | wc -l) == 1 ]]
file /usr/bin/bash | grep -q ELF
[[ $(echo "2^64" | bc) == 18446744073709551616 ]]
perl -e 'print "perl $^V works\n"'
python3 -c 'import ssl, ctypes, lzma, bz2, zlib; print("Python works, with", ssl.OPENSSL_VERSION)'
openssl version
[[ $(printf yurei | openssl dgst -sha256 -r | cut -d' ' -f1) == "$(printf yurei | sha256sum | cut -d' ' -f1)" ]]
# accounts (shadow)
useradd -m yurei-test
id yurei-test
userdel -r yurei-test
echo "core tools work"

# hardware support: firmware (compressed), the regulatory database, Wi-Fi
compgen -G '/usr/lib/firmware/iwlwifi-*.ucode.zst' > /dev/null
compgen -G '/usr/lib/firmware/i915/*.bin.zst' > /dev/null
[[ -f /usr/lib/firmware/regulatory.db && -f /usr/lib/firmware/regulatory.db.p7s ]]
/usr/lib/iwd/iwd --version
iwctl --help > /dev/null
sudo -V | head -n1
[[ $(stat -c %a /usr/bin/sudo) == 4111 || $(stat -c %a /usr/bin/sudo) == 4755 ]]
# the base of the desktop
wayland-scanner --version
pkg-config --modversion libdrm wayland-client wayland-protocols pixman-1 mtdev libevdev xkbcommon | tr '\n' ' '; echo
[[ -f /usr/share/X11/xkb/rules/evdev ]]
# the graphics stack: the compilers, then Mesa's drivers
cmake --version | head -n1
clang --version | head -n1
llvm-config --version
if pacman -Q mesa > /dev/null 2>&1; then
    glslangValidator --version | head -n1
    for f in /usr/lib/libEGL.so.1 /usr/lib/libGLESv2.so.2 /usr/lib/libgbm.so.1 \
             /usr/share/vulkan/icd.d/intel_icd.x86_64.json /usr/share/vulkan/icd.d/radeon_icd.x86_64.json; do
        [[ -e $f ]] || { echo "Mesa didn't install $f"; exit 1; }
    done
    echo "Mesa: OpenGL (iris, radeonsi, nouveau, llvmpipe) and Vulkan (anv, radv) installed"
fi
# the first graphical session: cage, foot and fonts
if pacman -Q cage > /dev/null 2>&1; then
    command -v cage yurei-desktop
    foot --version
    fc-list | grep -qi dejavu || { echo "fontconfig doesn't see the DejaVu fonts"; exit 1; }
    echo "cage, foot and fonts installed"
fi
# the desktop session: labwc on the toolkit base
if pacman -Q labwc > /dev/null 2>&1; then
    labwc --version
    pkg-config --modversion glib-2.0 cairo pango harfbuzz | tr '\n' ' '; echo
    [[ -f /etc/xdg/labwc/menu.xml && -f /etc/xdg/labwc/rc.xml ]]
    echo "labwc installed, with Yūrei's menu"
fi
# audio, GTK3 and the panel
if pacman -Q gtk3 > /dev/null 2>&1; then
    echo "GTK $(pkg-config --modversion gtk+-3.0)"
    pipewire --version | head -n2
    wireplumber --version | head -n1
    command -v sfwbar
    [[ -f /etc/xdg/labwc/autostart ]]
fi
# polkit, and the login shell's profile
if pacman -Q polkit > /dev/null 2>&1; then
    pkcheck --version
    [[ -f /etc/polkit-1/rules.d/40-yurei-wheel.rules && -f /etc/profile && -f /etc/profile.d/yurei-desktop.sh ]]
fi
# the X11 client libraries (for Xwayland)
if pacman -Q libx11 > /dev/null 2>&1; then
    pkg-config --exists x11 xcb xext xrender xfixes xi xrandr xcursor xtst xkbfile sm xshmfence xxf86vm
    pkg-config --modversion x11
fi
if pacman -Q xwayland > /dev/null 2>&1; then
    Xwayland -version 2>&1 | head -3
    [[ -x /usr/bin/xkbcomp ]]
fi
if pacman -Q thunar > /dev/null 2>&1; then
    # (Thunar needs a display to run, so only check it's there and links)
    [[ -x /usr/bin/thunar ]]
fi
# the Vulkan loader, and Mesa's Vulkan drivers it finds
if pacman -Q vulkan-icd-loader > /dev/null 2>&1; then
    [[ -f /usr/lib/libvulkan.so.1 && -x /usr/bin/vulkaninfo ]]
    ls /usr/share/vulkan/icd.d
fi
# HTTPS: the certificate list and GnuTLS
if pacman -Q gnutls > /dev/null 2>&1; then
    gnutls-cli --version | head -1
    [[ -f /etc/ssl/certs/ca-certificates.crt && -f /etc/ssl/cert.pem ]]
fi
# the Windows cross compilers: build a small threaded C++ program for
# 64- and 32-bit Windows (which also shows they work from /usr)
if pacman -Q mingw-w64 > /dev/null 2>&1; then
    x86_64-w64-mingw32-g++ --version | head -1
    printf '#include <thread>\nint main() { std::thread t([] {}); t.join(); }\n' > /tmp/mingw-test.cpp
    x86_64-w64-mingw32-g++ -o /tmp/mingw-test64.exe /tmp/mingw-test.cpp
    i686-w64-mingw32-g++ -o /tmp/mingw-test32.exe /tmp/mingw-test.cpp
    rm -f /tmp/mingw-test*
fi
# DXVK, for both kinds of Windows programs, and its setup command
if pacman -Q dxvk > /dev/null 2>&1; then
    ls /usr/share/dxvk/x64/d3d11.dll /usr/share/dxvk/x32/d3d9.dll
    command -v yurei-dxvk
fi
# Direct3D 12, GameMode, MangoHud, NVIDIA's driver, laptop sound
if pacman -Q vkd3d-proton > /dev/null 2>&1; then
    ls /usr/share/vkd3d-proton/x64/d3d12.dll /usr/share/vkd3d-proton/x86/d3d12.dll
fi
if pacman -Q gamemode > /dev/null 2>&1; then command -v gamemoderun; fi
if pacman -Q mangohud > /dev/null 2>&1; then
    command -v mangohud
    ls /usr/share/vulkan/implicit_layer.d/
fi
if pacman -Q nvidia-utils > /dev/null 2>&1; then
    ls /usr/lib/modules/*/kernel/drivers/video/nvidia/nvidia.ko /usr/share/vulkan/icd.d/nvidia_icd.json
    command -v nvidia-smi prime-run
fi
if pacman -Q sof-firmware > /dev/null 2>&1; then
    [[ -d /usr/lib/firmware/intel/sof || -d /usr/lib/firmware/intel/sof-ipc4 ]]
fi
if pacman -Q alsa-ucm-conf > /dev/null 2>&1; then [[ -d /usr/share/alsa/ucm2 ]]; fi
# the login screen: its helper refuses a wrong password, and its services
if pacman -Q yurei-greeter > /dev/null 2>&1; then
    if printf 'root\nnot-the-password\n' | /usr/lib/yurei/yurei-greeter check; then
        echo "the login screen took a wrong password" >&2
        exit 1
    fi
    [[ -f /usr/lib/systemd/system/yurei-greeter.service && -f /usr/lib/systemd/system/seatd.service ]]
fi
# Wine, and the linker its Windows side was built with
if pacman -Q wine > /dev/null 2>&1; then
    wine --version
    [[ -x /usr/bin/lld-link && -d /usr/lib/wine/x86_64-windows && -d /usr/lib/wine/i386-windows ]]
fi
# Qt 6: its paths, the Wayland and X11 screen plugins, and a QML scene with
# the imports Plasma's QML uses (drawn off screen, in software)
if pacman -Q qt6-base > /dev/null 2>&1; then
    /usr/lib/qt6/bin/qtpaths --qt-version
    [[ -f /usr/lib/qt6/plugins/platforms/libqxcb.so ]]
    if pacman -Q qt6-wayland > /dev/null 2>&1; then
        [[ -f /usr/lib/qt6/plugins/platforms/libqwayland-generic.so ]]
    fi
fi
if pacman -Q qt6-declarative qt6-5compat qt6-svg > /dev/null 2>&1; then
    qmltest=$(mktemp --suffix=.qml)
    printf '%s\n' 'import QtQuick' 'import Qt5Compat.GraphicalEffects' \
        'Item { width: 64; height: 64; Rectangle { id: r; anchors.fill: parent; color: "#7c5cff" }' \
        '  Glow { anchors.fill: r; source: r; radius: 4 }' \
        '  Component.onCompleted: { console.log("QML-OK"); Qt.quit() } }' > "$qmltest"
    # Qt is built with journald support. Force diagnostics into this captured
    # stream rather than a journal socket outside the fresh chroot.
    qmlout=$(QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 60 \
        /usr/lib/qt6/bin/qml "$qmltest" 2>&1) || true
    printf '%s\n' "$qmlout"
    [[ $qmlout == *QML-OK* ]]
    rm -f "$qmltest"
fi
if pacman -Q plasma-workspace > /dev/null 2>&1; then
    command -v startplasma-wayland kwin_wayland plasmashell systemsettings sddm
    cat > /tmp/yurei-plasma-imports.qml <<'QML'
import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
Item {
    Component.onCompleted: { console.log("PLASMA-QML-OK"); Qt.quit() }
}
QML
    qmlout=$(QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 60 \
        /usr/lib/qt6/bin/qml /tmp/yurei-plasma-imports.qml 2>&1) || true
    printf '%s\n' "$qmlout"
    [[ $qmlout == *PLASMA-QML-OK* ]]
    rm -f /tmp/yurei-plasma-imports.qml
fi
if pacman -Q yurei-install-gui > /dev/null 2>&1; then
    mkdir -p /tmp/yurei-gui-previews
    for page in 0 1 2 3 4 5; do
        QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen timeout 30 \
            yurei-install-gui --preview --page "$page" \
            --screenshot "/tmp/yurei-gui-previews/installer-$page.png"
    done
    python3 - <<'PY'
from pathlib import Path
import struct
for page in range(6):
    image = Path(f'/tmp/yurei-gui-previews/installer-{page}.png').read_bytes()
    assert image[:8] == b'\x89PNG\r\n\x1a\n'
    width, height = struct.unpack('>II', image[16:24])
    assert width >= 800 and height >= 600, (page, width, height)
print('All six native installer screens render with Yurei Qt')
PY
fi
echo "firmware $(du -sh /usr/lib/firmware | cut -f1), iwd works"

# every program and library finds what it links to
missing=
while IFS= read -r -d '' f; do
    lost=$(ldd "$f" 2>/dev/null | grep 'not found' | awk '{print $1}' | tr '\n' ' ') || true
    [[ -z $lost ]] || missing+="$f ($(pacman -Qoq "$f" 2>/dev/null)): $lost"$'\n'
done < <(find /usr/bin /usr/sbin /usr/lib -maxdepth 1 -type f -perm -u+x -print0)
if [[ -n $missing ]]; then
    echo "missing libraries (that package's depends is incomplete):"
    printf '%s' "$missing"
    exit 1
fi
if pacman -Q linux-pam > /dev/null 2>&1; then
    test -s /usr/lib/security/pam_systemd.so
    useradd -m -s /bin/bash yurei-pam-test
    printf 'yurei-pam-test:local-build-check-4872\n' | chpasswd
    cat > /tmp/yurei-pam-check.c <<'C'
#include <security/pam_appl.h>
#include <stdlib.h>
#include <string.h>
static int converse(int n, const struct pam_message **messages,
                    struct pam_response **out, void *data) {
    struct pam_response *r = calloc((size_t)n, sizeof(*r));
    if (!r) return PAM_BUF_ERR;
    for (int i = 0; i < n; ++i) {
        if (messages[i]->msg_style == PAM_PROMPT_ECHO_OFF)
            r[i].resp = strdup((const char *)data);
        else if (messages[i]->msg_style == PAM_PROMPT_ECHO_ON)
            r[i].resp = strdup("yurei-pam-test");
    }
    *out = r;
    return PAM_SUCCESS;
}
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    struct pam_conv conv = {converse, argv[1]};
    pam_handle_t *p = NULL;
    int status = pam_start("sudo", "yurei-pam-test", &conv, &p);
    if (status == PAM_SUCCESS) status = pam_authenticate(p, 0);
    if (status == PAM_SUCCESS) status = pam_acct_mgmt(p, 0);
    if (p) pam_end(p, status);
    return status == PAM_SUCCESS ? 0 : 1;
}
C
    cc /tmp/yurei-pam-check.c -lpam -o /tmp/yurei-pam-check
    /tmp/yurei-pam-check local-build-check-4872
    if /tmp/yurei-pam-check deliberately-wrong; then
        echo "PAM accepted an incorrect password" >&2
        exit 1
    fi
    userdel -r yurei-pam-test
    rm -f /tmp/yurei-pam-check.c /tmp/yurei-pam-check
    echo "PAM accepts the correct password and rejects the wrong password"
fi

# Check real timezone offsets, including seasonal and fractional offsets.
if pacman -Q tzdata >/dev/null 2>&1; then
    test "$(TZ=America/New_York date -d '2026-01-15 12:00:00 UTC' +%z)" = -0500
    test "$(TZ=America/New_York date -d '2026-07-15 12:00:00 UTC' +%z)" = -0400
    test "$(TZ=Asia/Kathmandu date -d '2026-01-15 12:00:00 UTC' +%z)" = +0545
    test -s /usr/share/zoneinfo/Etc/UTC
    echo "Timezone database handles winter, summer and fractional offsets"
fi

if pacman -Q fastfetch >/dev/null 2>&1; then
    timeout 30 fastfetch --config /etc/xdg/fastfetch/config.jsonc --pipe false > /tmp/yurei-fastfetch.txt
    grep -q 'Y U R E I' /tmp/yurei-fastfetch.txt
    grep -q 'Yūrei' /tmp/yurei-fastfetch.txt
    test -s /usr/share/fastfetch/yurei-logo.txt
    rm -f /tmp/yurei-fastfetch.txt
    echo "Fastfetch renders the Yurei mascot and detects the distro"
fi

if pacman -Q konsole >/dev/null 2>&1; then
    QT_QPA_PLATFORM=offscreen timeout 20 konsole --version
    QT_QPA_PLATFORM=offscreen timeout 20 dolphin --version
    timeout 20 firefox --version
    test -s /usr/share/applications/org.kde.konsole.desktop
    test -s /usr/share/applications/org.kde.dolphin.desktop
    test -s /usr/share/applications/firefox.desktop
    grep -qx 'inode/directory=org.kde.dolphin.desktop' /etc/xdg/mimeapps.list
    grep -qx 'x-scheme-handler/https=firefox.desktop' /etc/xdg/mimeapps.list
    echo "Konsole, Dolphin and Firefox start and their default applications are configured"
fi

if pacman -Q flatpak >/dev/null 2>&1; then
    timeout 20 flatpak --version
    timeout 20 bwrap --version
    timeout 20 xdg-dbus-proxy --version
    QT_QPA_PLATFORM=offscreen timeout 20 plasma-discover --version
    test -s /usr/share/flatpak/remotes.d/flathub.flatpakrepo
    test -s /usr/share/xdg-desktop-portal/portals/kde.portal
    echo "Discover, Flatpak, sandbox helpers and KDE portals are installed"
fi

echo "all libraries found"
