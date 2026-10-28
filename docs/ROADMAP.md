# Roadmap

## 0.1 — foundation
- [x] Build pipeline layered on CachyOS's live ISO profile (pinned upstream)
- [x] `yurei-settings` and `yurei-gaming` packages
- [x] Gaming stack installed by default; MangoHud defaults; gaming sysctl and NTSYNC
- [x] Steam Game Mode session (gamescope + Steam's console UI) with "Switch to Desktop"
- [x] `yurei` CLI: status, doctor --fix, update, bundles, drivers
- [x] Installer step that installs Yūrei packages into the target system
- [x] CI: lint, tests, package build; on-demand ISO build

## 0.2 — identity and updates
- [x] Signed `[yurei]` pacman repository on GitHub Releases (active once a signing key is added)
- [x] Logo, wallpaper (applied on first Plasma login) and boot menu splash
- [x] SteamOS-style session switching: `yurei session`, "Switch to Desktop", "Return to Game Mode"
- [ ] Build and boot the ISO; install on AMD, NVIDIA and Intel test machines

## 0.3 — mascot branding
- [x] Plymouth boot animation from the approved motion concept, with a waiting loop and a disk-unlock prompt
- [x] SDDM login theme with real controls, matching the approved design
- [x] `yurei bootsplash` and `yurei login-screen`, with backups and rollback; enabled by the installer
- [x] New wordmark in the ISO boot menu
- [ ] Test both on real hardware (NVIDIA early KMS, LUKS, multiple monitors)
- [ ] Clean high-resolution login art with the mascot on its own layer
- [ ] In-between poses for smoother running and leaping
- [ ] Plasma look-and-feel and Calamares branding

## 0.4 — polish
- [ ] Yūrei welcome app (GUI for bundles, doctor and drivers)
- [ ] Btrfs snapshots before every update, bootable from the boot menu
- [ ] Handheld support (Legion Go, ROG Ally, Steam Deck): controller, TDP and orientation fixes
- [ ] Per-game profiles: gamescope FSR/resolution, MangoHud preset, CPU scheduler

## Later
- [ ] Atomic/immutable variant
- [ ] Localised installer and docs
