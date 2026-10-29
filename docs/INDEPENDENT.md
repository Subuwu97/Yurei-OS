# Experiment: Yūrei as its own operating system

> **Status: stage 1 (toolchain) in progress.** On GitHub's runners, the
> cross toolchain builds from upstream source in about 16 minutes (GCC
> 15.2.0, glibc 2.42), and the temporary tools in 18; the chroot step,
> where Yūrei first builds by itself, is next. This repository, Yurei-OS,
> builds Yūrei without any other distribution underneath. The released Yūrei
> stays on CachyOS until this one can do everything it does.

**The goal:** Yūrei must keep going even if the distribution it's based on
today stops development or disappears. **Chosen approach: B** (below). Every
package is built from upstream source by Yūrei, and the tools it uses
(pacman, makepkg, archiso, Calamares) are open source, so Yūrei builds and
maintains its own copies of them too.

## What "its own OS" means

Today Yūrei is a layer on CachyOS: every package except `yurei-*` comes from
CachyOS's and Arch's repositories, and CachyOS's build machines, signing keys
and security updates keep it running.

An independent Yūrei would:

* **build every package from the original source code**, on Yūrei's own build
  machines, from Yūrei's own build recipes
* **publish its own package repositories**, signed with Yūrei's keys, and use
  no other distribution's repositories, at install time or afterwards
* **make its own decisions**: compiler flags, kernel configuration, which
  versions ship, and when
* **carry the responsibility too**: security fixes, broken updates and mirror
  hosting are Yūrei's job

Reusing *tools* doesn't make it less independent. Many independent
distributions use an existing package manager, compiler or installer, while
building and shipping everything themselves.

## How big this is

A gaming desktop like today's Yūrei is roughly:

| Layer | Packages (approx.) | Hardest parts |
|---|---|---|
| Toolchain and base system: compiler, C library, kernel, systemd, package manager, networking | 250–350 | Bootstrapping the compiler; the kernel configuration |
| Graphics and desktop: Mesa, Wayland, Qt 6, KDE Plasma and its apps | 700–900 | LLVM (Mesa needs it), Qt WebEngine (hours to compile), KDE's many parts |
| Gaming: 32-bit libraries (Steam needs them), Vulkan drivers, Steam, gamescope, MangoHud, Wine | 300–400 | The whole 32-bit library set, built a second time; the NVIDIA driver |
| Installer, firmware, fonts, apps (Firefox, etc.) | 200–300 | Firefox, compiled from source |
| **Total** | **~1,500–2,000** | |

After that come **weekly updates and security fixes** for all of them.
CachyOS and Arch have teams of people doing this. For a small project, the
work and the build computing power are the real limits.

**Build computing.** GitHub Actions gives private repositories 2,000 free
minutes a month, and each job can run for at most 6 hours. Today's ISO build
alone uses about 40 minutes. Rebuilding LLVM, Qt WebEngine or Firefox takes 1–3
hours each, and a full rebuild of everything takes days of CPU time. Public
repositories get unlimited free minutes on GitHub's standard runners, which
changes this a lot. Otherwise a home build server or a paid CI service would
be needed.

## Three ways to do it

### A. Completely from scratch

Your own package format and package manager, a system built like
[Linux From Scratch](https://www.linuxfromscratch.org/), and your own
everything.

* Most independent, and the most to learn from.
* Years of work before a gaming desktop. Every tool (package manager,
  dependency resolver, update system) has to be written and then kept working.

### B. Independent, built with existing tools (recommended)

Build every package from upstream source with Yūrei's own recipes, in the
format of an existing package manager (pacman/makepkg), on Yūrei's build
infrastructure, into Yūrei's own signed repositories.

* Nothing at runtime comes from another distribution, and every package is
  built by Yūrei.
* It reuses battle-tested tools: pacman, makepkg, archiso for the ISO, and
  Calamares for the installer. Arch's packaging recipes are published under the
  permissive 0BSD licence, so they can be studied and adapted as a starting
  point.
* Almost all of today's Yūrei work carries straight over: the themes, the
  `yurei` command, Steam Game Mode, the installer step and the branding.
* Still a large, ongoing job (see above), but one that can be done in stages,
  each ending in something that boots.

### C. Stay on CachyOS, but own more of it

Keep CachyOS underneath, and move more packages into Yūrei's own repository
over time (the kernel, Mesa, gaming tools).

* The least work, and it ships today.
* Not what this experiment is for, but a fallback that keeps everything
  usable.

## Plan for B, in stages

Each stage ends in something testable, built automatically in CI.

0. **Decisions.**
   * **CPU target:** x86-64-v3 like CachyOS, or v2 for older PCs.
   * **C library:** glibc, which Steam needs.
   * **Init system:** systemd, which Plasma and the Steam session expect.
   * **Package manager:** pacman.
   * **Repositories and mirrors:** where they live and who signs them.
1. **Bootstrap the toolchain.** In a container, build binutils, GCC and glibc
   from upstream tarballs, then rebuild them with themselves. The result is a
   minimal environment that can build Yūrei packages without any other
   distribution's packages. *Milestone: the toolchain rebuilds itself
   reproducibly.*
2. **Base system** (~300 packages). Kernel, systemd, pacman, networking, a
   shell. *Milestone: a Yūrei image boots to a login prompt in QEMU, in CI.*
3. **Graphics and desktop.** LLVM, Mesa, Wayland, Qt 6, KDE Plasma. *Milestone:
   the Plasma desktop with the Yūrei theme in a VM.*
4. **Gaming.** The 32-bit libraries, Vulkan drivers (AMD, Intel, NVIDIA),
   Steam, gamescope, MangoHud, GameMode. *Milestone: a Steam game runs, and
   Steam Game Mode works.*
5. **Installer and ISO.** Calamares with Yūrei's own configuration (today it
   uses CachyOS's), and the ISO from Yūrei's repositories. *Milestone: install
   on real hardware from a Yūrei-only ISO.*
6. **Running a distribution.** Update and security policy, signing keys,
   mirrors, a build queue that rebuilds what depends on an update.

## Decisions so far

| Decision | Choice | Why |
|---|---|---|
| Approach | B: Yūrei's own packages, built with existing open-source tools | Independence without years of reinventing tools |
| C library | glibc | Steam and most games need it |
| Target triplet | `x86_64-yurei-linux-gnu` | Yūrei's own; keeps the bootstrap apart from the host |
| Sources | Official upstream release tarballs only, pinned by SHA-256 in `independent/bootstrap/sources.lock` | Nothing comes from another distribution |
| Build power | GitHub Actions in this public repository | Unlimited free minutes on standard runners (6 hours per job); bigger jobs may later need a larger runner or a build PC |
| CPU target | Decided at stage 2 | x86-64-v3 like CachyOS is faster; v2 runs on older PCs |

## To do

* Check the pinned source checksums against upstream's GPG signatures
  (`.sig` files for GNU, `.sign` for kernel.org), and do so automatically
  for new sources.

## What this repository contains

* `docs/INDEPENDENT.md`: this plan, and the decisions as they're made
* `independent/bootstrap/`, built by the *Independent bootstrap* workflow
  whenever it changes:
  * `stage1.sh`: the cross toolchain (binutils, GCC, Linux headers, glibc,
    libstdc++)
  * `temptools.sh`: the basic tools (bash, coreutils, make, sed, tar, xz,
    …) and a native binutils and GCC, all built for Yūrei with that
    toolchain
  * `chroot.sh` (with `chroot-inside.sh`): enters the new system and builds
    gettext, bison, perl, Python, texinfo and util-linux inside it, with
    Yūrei's own compiler; the host provides only the kernel

## Naming

The system is simply **Yūrei** ("Yūrei Linux" in full), like Debian, Arch
or Fedora. "Yurei-OS" is only this repository's name. Machine-readable IDs
use `yurei` (`ID=yurei` in os-release, the `x86_64-yurei-linux-gnu`
toolchain), and boot menus show "Yurei", because they can't draw "ū".
Releases are rolling, with dated ISOs (`2026.10.28`).

None of it touches the released Yūrei on CachyOS.
