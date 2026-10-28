# Yūrei name, logo and mascot

"Yūrei" and "Yūrei Linux", the Yūrei wordmark, the moon-ghost icon and the
Yūrei mascot identify this project. This policy explains how you can use them.
It's modelled on the policies of Arch Linux and Fedora. In short: share Yūrei
freely, but don't present something else as Yūrei.

These marks are not registered; "™" may be used to indicate them.

## You may, without asking

* Redistribute **unmodified** Yūrei ISOs and packages under the Yūrei name.
* Write about Yūrei, review it, make videos of it, and use the logo and mascot
  to illustrate that.
* Make fan art and community content (wallpapers, stickers, themes), as long
  as it doesn't look official and isn't sold as official merchandise.
* Link to the project with the logo.
* Use the marks in your own installs, screenshots and presentations.

## Please don't

* **Ship a modified system as "Yūrei".** If you change what's installed or
  how it works, the code licence (GPL) lets you, but use your own name and
  logo, and remove or replace the Yūrei branding. You may say it's "based on
  Yūrei".
* Use the marks in a way that suggests the project endorses you, your product
  or your service.
* Use the name, logo or mascot as part of your own product, company or
  domain name.
* Sell merchandise with the marks without permission.

## Removing the branding from a fork

The branding is kept in a few places, so rebranding is a small job:

| What | Where |
|---|---|
| Artwork sources | `branding/` |
| Generated themes | `themes/`, regenerated with `make assets` |
| Wallpaper and icon | `pkg/yurei-settings/files/usr/share/{wallpapers,icons,pixmaps}` |
| System name | `pkg/yurei-settings/files/usr/lib/yurei/os-release` and `overlay/airootfs/etc/os-release` |
| Boot menu | `overlay/boot/splash.png`, plus the `Yurei` boot entry names set in `build.sh` |

## Questions and permission

Open an issue at https://github.com/subuwu97/Y-rei-Linux/issues.
