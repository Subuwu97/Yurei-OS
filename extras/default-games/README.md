# Default visual novels: preinstallation preparation

Requested games: the original Katawa Shoujo and Doki Doki Literature Club.
This is staging work, excluded from package ORDER, repositories and ISO builds.
No game assets are included, downloaded, modified or redistributed here. The
manifests intentionally have no verified entrypoints or archive hashes yet.

## Published builds checked

- [Four Leaf Studios on itch.io](https://4leafstudios.itch.io/katawa-shoujo)
  lists Katawa Shoujo 1.3.2 and a Linux-x86 tar.zst download (481 MB).
- [Team Salvato on itch.io](https://teamsalvato.itch.io/ddlc) lists DDLC 1.1.1
  and Linux as a supported platform. The precise archive contents and native
  executable still need verification.
- [Team Salvato's IP guidelines](https://teamsalvato.com/ip-guidelines), checked
  2026-10-31, explicitly do not grant a redistribution license. Their fangame
  rules are not permission to bundle the original game in a distro. Establish
  the applicable redistribution terms or obtain written permission before
  publishing the payload. No claim about Katawa Shoujo's complete distribution
  terms is made here until its actual license files have been inspected.

## Install layout once each payload is verified

- Install the launcher as `/usr/bin/yurei-game` (mode 0755; requires Python 3).
- Install a verified manifest as `/usr/share/yurei/games/ID.json`.
- Keep the upstream game tree intact at `/usr/share/yurei/games/ID/payload/`.
- Install the matching desktop entry under `/usr/share/applications/` only
  when the actual game payload and runtime are included.
- The first launch copies the payload to `$XDG_DATA_HOME/yurei/games/ID/`
  (normally `~/.local/share/yurei/games/ID/`). Later launches reuse that copy.
  This costs additional disk space but preserves separate playthroughs and
  supports games that change files in their own directories. A changed package
  version currently stops with a migration message instead of resetting saves.

## Remaining before activating preinstallation

1. Acquire the original archives from the official pages, retain their license
   and attribution files, and pin verified SHA-256 values. The selected game
   editions and their content notices must be explicit; no additional patches
   are selected by this preparation work.
2. Establish redistribution rights for each exact payload and distribution use.
3. Inspect native executables, ELF interpreters and library dependencies. The
   Linux-x86 label is not proof it runs on Yurei's current 64-bit-only system.
   Test 32-bit requirements rather than assuming Wine or 64-bit glibc solves them.
4. Record the real entrypoint and validate first launch, audio, fullscreen,
   saves, file-changing game behavior, two different users, and upgrades inside
   Yurei. Do not modify the game to bypass its own content notices.
5. Package only the verified payload, launcher and desktop entry, then explicitly
   add those packages to the default image. Add migration support before shipping
   a game update that changes the version.

The launcher mechanics can be tested without copyrighted game data:
`python3 -m pytest -q tests/test_default_games.py`.
