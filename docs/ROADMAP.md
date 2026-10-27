# Roadmap

## 0.1 — foundation (this release)
- [x] Build pipeline layered on CachyOS's live ISO profile (pinned upstream)
- [x] `yurei-settings` and `yurei-gaming` packages
- [x] Gaming stack installed by default; MangoHud defaults; gaming sysctl and NTSYNC
- [x] Steam Game Mode session (gamescope + Steam's console UI) with "Switch to Desktop"
- [x] `yurei` CLI: status, doctor --fix, update, bundles, drivers
- [x] Installer step that installs Yūrei packages into the target system
- [x] CI: lint, tests, package build; on-demand ISO build

## 0.2 — first boot
- [ ] Build and boot the ISO; install on AMD, NVIDIA and Intel test machines
- [ ] Signed `[yurei]` pacman repository (GitHub Releases) so `yurei-*` updates arrive through `pacman -Syu`
- [ ] Visual identity: wallpaper, Plasma look-and-feel, boot splash, login theme, Calamares branding
- [ ] Choose the default session (desktop or Steam Game Mode) from `yurei` and the welcome app

## 0.3 — polish
- [ ] Yūrei welcome app (GUI for bundles, doctor and drivers)
- [ ] Btrfs snapshots before every update, bootable from the boot menu
- [ ] Handheld support (Legion Go, ROG Ally, Steam Deck): controller, TDP and orientation fixes
- [ ] Per-game profiles: gamescope FSR/resolution, MangoHud preset, CPU scheduler

## Later
- [ ] Atomic/immutable variant
- [ ] Localised installer and docs
