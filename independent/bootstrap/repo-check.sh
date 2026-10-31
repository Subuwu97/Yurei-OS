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
# Wine, and the linker its Windows side was built with
if pacman -Q wine > /dev/null 2>&1; then
    wine --version
    [[ -x /usr/bin/lld-link && -d /usr/lib/wine/x86_64-windows && -d /usr/lib/wine/i386-windows ]]
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
echo "all libraries found"
