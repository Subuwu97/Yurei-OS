# Yūrei 幽霊

**A gaming-first desktop Linux built on CachyOS, ready for everything else too.**

Yūrei ("ghost") starts from CachyOS: an Arch-based system with the
BORE/sched-ext kernel, packages compiled for modern CPUs (x86-64-v3/v4/Zen 4),
and automatic GPU driver setup. On top of that it adds a complete gaming setup
out of the box, a console-style Steam mode, and one command for keeping it all
running well.

## What you get

**Gaming, installed and configured**
- Steam, Proton (CachyOS build), Wine, Lutris, Heroic (Epic/GOG/Amazon) and umu-launcher.
  They come from CachyOS's own `cachyos-gaming-meta` and `cachyos-gaming-applications` packages.
- GameMode, gamescope, and MangoHud with a clean default overlay (toggle with **Right Shift + F12**).
- **Steam Game Mode session.** Pick *Steam Game Mode (Yūrei)* at the login screen to get Steam's
  console interface full-screen with VRR and HDR, like a Steam Deck. *Switch to Desktop* in
  Steam's power menu returns you to the login screen.
- Tuning for games: `vm.max_map_count` as on SteamOS, no split-lock throttling, and NTSYNC for
  Wine/Proton. CachyOS adds its kernel, scheduler, zram and I/O tuning on top.
- Automatic NVIDIA/AMD/Intel driver setup with CachyOS's `chwd`.

**Ready for everything else**
- KDE Plasma desktop, Firefox, Flatpak with Flathub, and the AUR through `paru`.
- Optional app bundles, one command each:

| Bundle | What's in it |
|---|---|
| `streaming` | OBS Studio with Vulkan/OpenGL game capture, Discord |
| `emulation` | RetroArch, Dolphin, PCSX2, DuckStation, RPCS3, PPSSPP, Cemu, Azahar |
| `launchers` | Bottles, ProtonPlus, Prism Launcher (Minecraft), itch |
| `creative` | Blender, Krita, GIMP, Kdenlive, Inkscape, Audacity |
| `office` | LibreOffice, Thunderbird, Okular, KeePassXC |
| `dev` | Compilers, Git, GitHub CLI, Docker, Podman, VS Code (OSS), Neovim, Python, Node, Rust, Go |
| `vr` | WiVRn (stream PC VR to standalone headsets) |

## The `yurei` command

```text
yurei status            What this machine is running (kernel, scheduler, GPU, power profile)
yurei doctor [--fix]    Check the gaming essentials (multilib, Vulkan + 32-bit drivers,
                        GameMode group, NTSYNC, Flathub, map count) and repair them
yurei update            Update system packages, AUR packages and Flatpaks
yurei bundles           List app bundles
yurei install BUNDLE... e.g. yurei install streaming emulation
yurei drivers           Detect hardware and install the right GPU drivers
```

## How it's built

Yūrei is built as a layer on top of CachyOS's official ISO profile, so CachyOS's
installer, boot setup and hardware detection keep working and stay easy to
update:

```
upstream.conf          pinned commit of github.com/CachyOS/CachyOS-Live-ISO
pkg/yurei-settings/    PKGBUILD for two packages:
  yurei-settings         branding, tuning, the yurei CLI, Steam Game Mode session, bundles
  yurei-gaming           meta package pulling in the gaming stack
overlay/
  packages.add/.remove   changes to CachyOS's ISO package list
  airootfs/              files placed on the live ISO (branding, installer step)
build.sh               builds the packages, fetches upstream, applies the overlay, builds the ISO
```

During installation, CachyOS's Calamares installer runs one extra step,
`yurei-install-target`. It installs the `yurei-*` packages shipped on the ISO
into the new system and gives every user access to GameMode.

### Building the ISO

On a CachyOS machine (it needs CachyOS's repositories and keys):

```sh
sudo pacman -S --needed archiso mkinitcpio-archiso git squashfs-tools grub base-devel
git clone https://github.com/subuwu97/Y-rei-Linux && cd Y-rei-Linux
./build.sh            # run as your normal user; asks for sudo when building the image
# → out/yurei-YYYY.MM.DD-x86_64.iso (+ .sha256)
```

You can also run the **Build ISO** GitHub Actions workflow, which builds it in
CachyOS's container image.

### Trying it on an existing CachyOS install

```sh
cd pkg/yurei-settings && makepkg -si
```

That installs `yurei-settings` and `yurei-gaming`, which gives you everything
except the installer and live-ISO branding.

### Tests

`make lint test` runs shellcheck, tests the CLI against stubbed
pacman/flatpak, tests the installer patch, and applies the overlay to the
pinned CachyOS profile to check that every change still lands. Run it after
bumping `UPSTREAM_REF`.

## Status

Early, working scaffold (0.1). The overlay is tested against the pinned
CachyOS profile and the CLI is tested with stubs. **The full ISO has not yet
been built and booted.** That needs a CachyOS host or the ISO workflow. See
[docs/ROADMAP.md](docs/ROADMAP.md).

Yūrei is an independent project and isn't affiliated with or endorsed by
CachyOS. Many thanks to the CachyOS team, whose work it builds on.
