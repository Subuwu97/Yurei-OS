# Artwork

## Where it comes from

Yūrei's mascot, wordmark, wallpaper, login design and boot animation were
created with **ChatGPT (OpenAI)** image generation. The Yūrei project directed
the results and selected and edited them. We say so openly because people
reasonably want to know how the art they see was made.

| File | Made with | Used for |
|---|---|---|
| `branding/source/Yurei-Logo.png` | ChatGPT | Wordmark (login screen, boot menu) |
| `branding/source/Yurei-Login-Reference.png` | ChatGPT | Login screen background and default avatar |
| `branding/source/Yurei-Wallpaper.png` | ChatGPT | Desktop and lock screen wallpaper |
| `branding/source/Yurei-Boot-Animation.mp4` | ChatGPT | Boot animation |
| `branding/source/Yurei-Animation-Poses.png` | ChatGPT | Character reference |
| `branding/source/Yurei-Desktop-Reference.png` | ChatGPT | Design reference for the default desktop |
| `branding/icon.svg` | Drawn as SVG by Claude (Anthropic), after the ChatGPT logo | App menu, dock and system icon |

Everything under `themes/` (boot animation, login screen, Plasma splash), the
wallpaper package, `overlay/boot/splash.png` and the installer's images in
`overlay/airootfs/usr/share/calamares/branding/yurei/` are derived from those
files by `branding/build-assets.py`. It removes captions
and mock-up controls, cuts out the wordmark, picks animation frames, and so on.

### Provenance log

Keep a record here as art is made or changed: the date, the tool, the prompt
or brief, and what was edited by hand. It helps show where human work was
added, and it keeps track of which version is current.

| Date | File | Tool | Prompt / brief | Human edits |
|---|---|---|---|---|
| 2026-10 | (initial set above) | ChatGPT | *(add prompts if you still have them)* | Selection; mock-up UI and captions removed in `build-assets.py` |

## Licence

To the extent that copyright or similar rights exist in this artwork, it is
licensed under **[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)**.
You may share and adapt it, including commercially, if you credit "Yūrei Linux"
and share your adaptations under the same licence.

Two things to be aware of:

* **AI-generated images may have no copyright.** In the United States and
  many other places, images generated purely by AI from text prompts are not
  protected by copyright. The licence above covers whatever rights do exist,
  such as human edits and arrangement.
* **The licence covers the artwork, not the brand.** CC BY-SA grants no
  rights to the Yūrei name, logo or mascot as identifiers of this project.
  See [TRADEMARKS.md](TRADEMARKS.md).

The code (scripts, themes' QML and Plymouth script, packaging) is licensed
under GPL-3.0-or-later.

## Plans

The aim is to commission a human artist for an official character reference
sheet and clean, high-resolution login art built from these designs. That
would make the mascot's details consistent across pictures, and give the
project artwork it clearly owns.
