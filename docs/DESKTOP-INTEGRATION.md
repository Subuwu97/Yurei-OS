# Combined independent desktop image

Target: one source-built image with Qt, Plasma as the default Wayland desktop,
labwc as the fallback, and the native graphical installer in the live session.

This branch combines the tested ISO recovery fixes, the native installer from
PR #7, and Claude's first KDE Frameworks tier with the protocol fix from PR #8.
It does not yet include a working Plasma shell/session. The known-good test
ISO remains available while integration proceeds.

Current build milestone:

- Keep the already-built Qt/labwc/gaming packages and their cached recipes.
- Compile and package the native installer with Yurei's own Qt.
- Render all six installer screens inside the freshly installed Yurei root.
- Build ECM, Plasma Wayland protocols and the first Frameworks tiers.
- The next 19 Frameworks recipes use dependencies read from the verified 6.18
  upstream CMake files; runtime compilation is still being validated.
- Qt Sensors, Positioning and Location 6.9.3 recipes are pinned for KWin and
  Plasma workspace; these still need compilation on the runner.
- The next dependency batch adds notification audio codecs, client-only
  libpulse, libcanberra, Polkit Qt 6 and five additional Frameworks.
  PipeWire remains the audio server; these recipes still require build validation.
- Recheck clean installation, shared libraries, ISO boot and installation.

Remaining before the target image can be called Plasma-ready:

- Remaining required KDE Frameworks and their system dependencies.
- PAM/logind session integration and a working desktop authentication agent.
- KWin, libplasma, Plasma workspace/desktop and their dependency graph.
- SDDM with Plasma default and labwc available as a fallback session.
- System settings, Breeze assets and independent Yurei appearance defaults.
- Real graphical VM login, compositor, panel, installer authorization and
  installation checks. Offscreen rendering alone does not establish these.

No KDE binaries are taken from Arch or CachyOS. Source release archives and
checksums stay pinned in sources.lock. Existing users' personal desktop
configuration must be preserved.

During dependency bring-up, BUILD_DESKTOP_ISO is false in the integration
workflow: package/GUI validation and cached results are produced each cycle.
Enable it for the final combined image after the Plasma session is assembled.

Validated milestone: all 262 packages in the previous batch installed cleanly,
all six native installer screens rendered, and the shared-library audit passed.
The next seven recipes add KIO, KParts, KCMUtils, KRunner, KNewStuff, the
Qt Quick desktop style and Purpose. Their builds remain to be validated.
KIO will need rebuilding with Wallet once the wallet runtime dependencies land.
