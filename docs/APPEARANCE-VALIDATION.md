# Appearance validation

The shared reference is `themes/` and the visual files under
`pkg/yurei-settings/files/`. Both builds should ship those same assets.
Build recipes, workflow changes and `yurei-appearance` are maintained separately
from this validation work.

## Package contents

Extract the built appearance package into an empty directory, or use a mounted
system root, then run from the repository:

```sh
python3 tests/check_appearance_payload.py /path/to/root
```

The checker reads the target without changing it. It compares the Plasma,
SDDM and Plymouth assets, colours, wallpapers, icons, Konsole files, and the
generated dock layout with their source bytes. Extra files are allowed.
It does not check dependencies, activation of defaults, or visual rendering.
Run against the matching source commit: different source revisions may have
legitimately different assets. For byte comparisons, use the Linux checkout
used for packaging; Windows Git checkouts may convert text line endings.
The target directory must be trusted; the
checker follows filesystem symlinks when reading files.

## Existing behaviour and rendering checks

```sh
node tests/test_desktop_layout.js
bash tests/test_theme_defaults.sh
python3 -m pytest -q tests/test_sddm_theme.py tests/test_branding_qml.py
```

The SDDM bounds checks cover nine logical window sizes, from 1280x720 to
4K, plus ultrawide and portrait. Set `YUREI_SCREENSHOTS` to an output directory
to save a login-screen image at each size (CI keeps these in `theme-screenshots`).
These window-size checks do not simulate Qt fractional scaling or mixed-DPI
monitors; those remain part of real-session validation below.

Qt checks require PySide6; a skipped module is not a rendering pass. These use
stand-in APIs and do not establish that a real Plasma session works. See
`docs/THEMES.md` for Plymouth and theme rendering instructions.
The SDDM preview defaults to Qt's portable Basic controls style. For offscreen
previews on Windows, set `QT_QPA_FONTDIR` to a directory containing fonts,
such as `C:/Windows/Fonts`; use matching fonts when comparing screenshots.

## Real-session acceptance

Compare the existing Yurei desktop and independent build with the same
application set, fonts, resolution and scaling. Record the source commit,
package versions, session type, GPU, resolution and scale with screenshots.
Never use screenshots containing real passwords or private account details.

Check both the live ISO and an installed system, including a newly created user:

- Boot animation, SDDM, Plasma splash, desktop and lock screen use Yurei assets.
- Colours, wallpaper, Breeze icons/cursor/decoration and Konsole profile match.
- Top bar, floating dock, launcher order and tray applets match the intended set.
  Record intentionally deferred apps rather than treating missing launchers as a pass.
- Check 1080p at 100%, 1440p at 125% and 150%, 4K at 200%, ultrawide and portrait.
  Controls must remain usable, without clipping or overlapping. Matching identity
  does not require identical physical geometry at every resolution.
- Check login, logout, lock/unlock, suspend/resume and display hotplug. Hardware
  checks must include the GPU and monitor combinations actually supported.
- Upgrades preserve user-customized panels and settings; fresh users receive the
  defaults. The installer launcher appears only where it is usable.

VM screenshots can establish an initial visual comparison. Hardware testing is
still needed for graphics drivers, mixed-scale monitors and boot handoff.
