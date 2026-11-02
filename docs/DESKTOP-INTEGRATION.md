# Combined independent desktop image

Target: one source-built image with Plasma as the default Wayland desktop,
labwc as the fallback, and the native graphical installer in the live session.

Validated at commit 3f8a25a: 291 packages installed cleanly, all six native
installer screens rendered with Yurei Qt, and the shared-library audit passed.
This includes Qt 6.9.3, the required initial Frameworks tiers, wallet, media,
speech and text components, and the first Plasma platform libraries and
Polkit authentication agent. This is not yet a complete Plasma session.

The next batch adds PAM authentication to systemd, shadow, sudo and Polkit.
PAM is explicitly installed early during repository builds so systemd and
shadow can link it even when the prerequisite package comes from the cache.
A regression check covers early installation without enabling installation
of every core bootstrap recipe. The clean-root check exercises correct and
incorrect password authentication through the distro's actual PAM modules.

That batch also builds lcms2, QCoro, libplasma, Plasma5Support, the activity
manager, Breeze, System Settings, KDE CLI tools and KScreenLocker. Compilation
and PAM behavior are still awaiting runner validation.

Remaining: KWin, Plasma workspace/desktop, their remaining dependencies,
SDDM, session integration, independent Yurei appearance defaults and final
UEFI boot, graphical login, installer and installed-system checks. Existing
user configuration must be preserved. No Arch or CachyOS binaries are used.

BUILD_DESKTOP_ISO remains false during dependency bring-up. Enable it only
once the complete session is assembled; then rebuild and verify one combined
image. The previously tested Qt/labwc ISO remains available in outputs.

The assembled-shell batch adds KWin, Plasma workspace/desktop, libksysguard,
Phonon with its VLC audio backend and SDDM. The launcher selects Plasma when
available and exposes labwc explicitly; SDDM uses Wayland and PAM/logind.
These builds and runtime integration checks are still pending. Qt Multimedia
provides FFmpeg playback; the smaller VLC build is for Phonon desktop audio.

PAM and the shell-library batch passed: 301 packages installed cleanly,
correct/wrong-password checks behaved as expected, native installer previews
rendered, and all libraries were found. Phonon built; the VLC helper compiler
needs BUILDCC=gcc explicitly on this from-scratch toolchain.

The independent appearance payload stages shared visual files directly from
the repository before recipe hashing. It does not import distribution tools
or sudoers rules. Shared themes remain byte-identical; generated dock scripts
select Foot, Thunar and the graphical installer, omitting absent browser and
commercial launchers. Plymouth artwork is included but boot animation is
not yet wired into the installed boot path.

The final disposable-VM checks now target SDDM and actual KWin/Plasma
processes, collect screenshots, and type the test password into SDDM. These
graphical checks are not yet validated. The live-only passwordless root
console uses a live-only PAM exception; installed accounts retain normal PAM.
