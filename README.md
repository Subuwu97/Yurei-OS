# Yurei-OS

**Yūrei as its own Linux operating system.**

Yūrei (幽霊, "ghost") is a gaming-first desktop. It started as a layer on
CachyOS. This repository is where it becomes independent: every package
built by Yūrei from the original source code, into Yūrei's own repositories,
so it keeps going whatever happens to any other distribution.

* **The plan, the decisions and the progress:** [docs/INDEPENDENT.md](docs/INDEPENDENT.md)
* **The independent build:** [independent/](independent/). Stage 1, the compiler
  toolchain, is in progress.
* **Everything below** is the Yūrei desktop as it is today, built on CachyOS:
  the themes, the `yurei` command, Steam Game Mode and the installer step.
  It all carries over to the independent system.

---

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
- **Steam Game Mode, SteamOS-style.** Steam's console interface runs full-screen with VRR and HDR,
  like a Steam Deck. Run `yurei session game` to boot straight into it. *Switch to Desktop* in
  Steam's power menu then drops you into Plasma, and the **Return to Game Mode** icon takes you
  back. With `yurei session off` it's simply an option at the login screen.
- Tuning for games: `vm.max_map_count` as on SteamOS, no split-lock throttling, and NTSYNC for
  Wine/Proton. CachyOS adds its kernel, scheduler, zram and I/O tuning on top.
- Automatic NVIDIA/AMD/Intel driver setup with CachyOS's `chwd`.

**Ready for everything else**
- **Yūrei from the first screen.** While the system starts, the mascot chases and catches a
  spirit, then waves while booting finishes, and keeps waving while the desktop loads. The login
  screen is a moonlit shrine with the mascot, the new wordmark, and real controls. The live ISO
  and the installer are themed too, with Yūrei slides while it installs.
  See [docs/THEMES.md](docs/THEMES.md).
- **Its own desktop theme:** the Yūrei global theme gives windows, panels, menus and the terminal
  the boot animation's navy and the login screen's lavender, with sakura pink, lantern gold and
  spirit blue for warnings and links. It's the default for every account, and is listed as
  *Yūrei* under System Settings > Global Theme.
- **A macOS-style desktop by default:** a slim top bar (Yūrei menu, app menus, centred clock,
  tray) and a floating dock (app grid, Files, Firefox, Terminal, Settings, Discover, Steam,
  Discord, Trash) over the mascot wallpaper. Use `yurei layout classic` for a single bottom
  panel instead.
- KDE Plasma desktop with Yūrei's boot menu, Firefox, Flatpak with Flathub, and
  the AUR through `paru`.
- Updates to Yūrei's own packages come from a signed `[yurei]` pacman repository
  (see [docs/REPOSITORY.md](docs/REPOSITORY.md)).
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
yurei session MODE      Start in game (Steam Game Mode), desktop, or off (login screen)
yurei login-screen X    yurei (the Yūrei login screen) or plasma (CachyOS's default)
yurei bootsplash X      on or off: the animated boot screen (with backups and full rollback)
yurei layout X          dock (top bar and macOS-style dock) or classic (one bottom panel)
yurei theme X           yurei (navy and lavender) or breeze (Plasma's Breeze Dark)
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
  boot/splash.png        boot menu background
branding/              design sources; `make assets` (build-assets.py) builds the boot animation,
                       login artwork and boot menu from branding/source/
themes/                the Plymouth boot animation and the SDDM login theme
keys/                  public key of the [yurei] repository (see docs/REPOSITORY.md)
build.sh               builds the packages, fetches upstream, applies the overlay, builds the ISO
```

On the live ISO, **Install Yūrei** (first in the dock) starts CachyOS's
Calamares installer with Yūrei's branding. It runs one extra step,
`yurei-install-target`, which installs the GPU's Vulkan drivers and the
`yurei-*` packages shipped on the ISO into the new system, turns on the boot
animation and login screen, names the boot menu entry, and gives every user
access to GameMode.

### Getting the ISO

**From GitHub (no CachyOS machine needed):** open the repository's
*Actions* tab, choose **Build ISO**, then **Run workflow**. It takes about
an hour. The result appears under *Releases* as a pre-release, split into
parts because GitHub limits files to 2 GB. Download all the parts and the
`.sha256` file, then join them:

```sh
cat yurei-*.iso.part* > yurei.iso      # Windows: copy /b part01 + part02 + part03 yurei.iso
sha256sum yurei.iso                    # compare with the .sha256 file
```

Write it to a USB stick with Ventoy, balenaEtcher or Rufus (DD mode), or boot
it in a VM such as VirtualBox, GNOME Boxes or virt-manager (give it 4+ GB RAM).

### Building the ISO yourself

On a CachyOS machine (it needs CachyOS's repositories and keys):

```sh
sudo pacman -S --needed archiso mkinitcpio-archiso git squashfs-tools grub base-devel
git clone https://github.com/subuwu97/Y-rei-Linux && cd Y-rei-Linux
./build.sh            # run as your normal user; asks for sudo when building the image
# → out/yurei-YYYY.MM.DD-x86_64.iso (+ .sha256)
```

Allow about 30 GB of free disk space and an hour.

### Trying it on an existing CachyOS install

```sh
cd pkg/yurei-settings && makepkg -si
```

That installs `yurei-settings` and `yurei-gaming`, which gives you everything
except the installer and live-ISO branding.

### Tests

`make lint test` runs shellcheck, tests the CLI against stubbed
pacman/flatpak, the session switcher against throwaway login-manager configs,
the installer step against a fake target system, and the Calamares patch.
It also applies the overlay to the pinned CachyOS profile to check that every
change still lands. Run it after
bumping `UPSTREAM_REF`.

## Status

Early development (0.4). The overlay is tested against the pinned
CachyOS profile and the CLI is tested with stubs. **The full ISO has not yet
been built and booted.** That needs a CachyOS host or the ISO workflow. See
[docs/ROADMAP.md](docs/ROADMAP.md).

## Experiment: an independent Yūrei

The `experimental/independent` branch explores building Yūrei without any
distribution underneath; see [docs/INDEPENDENT.md](docs/INDEPENDENT.md).

## Artwork and branding

The mascot and artwork were made with ChatGPT and adapted for Yūrei. See
[ARTWORK.md](ARTWORK.md) for where each piece comes from and its licence
(CC BY-SA 4.0, to the extent rights exist). The Yūrei name, logo and mascot
are covered by [TRADEMARKS.md](TRADEMARKS.md): share Yūrei freely, but forks
that change it need their own name and logo.

Yūrei is an independent project and isn't affiliated with or endorsed by
CachyOS. Many thanks to the CachyOS team, whose work it builds on.
