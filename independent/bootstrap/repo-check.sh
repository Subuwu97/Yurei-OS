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
