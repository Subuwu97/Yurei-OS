.PHONY: test test-themes assets lint package prepare iso clean

SHELL_SCRIPTS = build.sh tests/*.sh overlay/airootfs/usr/local/bin/yurei-install-target \
                pkg/yurei-settings/files/usr/lib/yurei/session-select pkg/yurei-settings/files/usr/bin/yurei-return-to-gamemode \
                pkg/yurei-settings/files/usr/lib/yurei/login-screen pkg/yurei-settings/files/usr/lib/yurei/bootsplash \
                pkg/yurei-settings/files/usr/bin/yurei pkg/yurei-settings/files/usr/bin/yurei-steam-session \
                pkg/yurei-settings/files/usr/bin/steamos-session-select

test:
	tests/test_cli.sh
	tests/test_session.sh
	tests/test_install_target.sh
	tests/test_bootsplash.sh
	node tests/test_desktop_layout.js
	python3 -m pytest -q tests
	tests/test_overlay.sh

# Runs the real themes: the SDDM theme in Qt 6 (needs PySide6) and Plymouth
# in a virtual display (needs root, plymouth's X11 renderer, Xvfb, xdotool,
# ImageMagick). See docs/THEMES.md.
test-themes:
	python3 -m pytest -q tests/test_sddm_theme.py
	sudo python3 tests/plymouth_check.py --out out/theme-screenshots

# Regenerate theme assets from branding/source/ (needs ffmpeg, Pillow,
# numpy, opencv-python-headless)
assets:
	python3 branding/build-assets.py

lint:
	shellcheck -x $(SHELL_SCRIPTS)

# Needs makepkg (Arch/CachyOS)
package:
	cd pkg/yurei-settings && PKGDEST=$(CURDIR)/out/packages makepkg --force --cleanbuild --nodeps

prepare:
	./build.sh --prepare-only

# Needs CachyOS with archiso; see README
iso:
	./build.sh

clean:
	rm -rf out pkg/yurei-settings/src pkg/yurei-settings/pkg .pytest_cache
	[ ! -d work ] || sudo rm -rf work
