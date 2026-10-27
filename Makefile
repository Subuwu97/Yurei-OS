.PHONY: test lint package prepare iso clean

SHELL_SCRIPTS = build.sh tests/*.sh overlay/airootfs/usr/local/bin/yurei-install-target \
                pkg/yurei-settings/files/usr/lib/yurei/session-select pkg/yurei-settings/files/usr/bin/yurei-return-to-gamemode \
                pkg/yurei-settings/files/usr/bin/yurei pkg/yurei-settings/files/usr/bin/yurei-steam-session \
                pkg/yurei-settings/files/usr/bin/steamos-session-select

test:
	tests/test_cli.sh
	tests/test_session.sh
	tests/test_install_target.sh
	python3 -m pytest -q tests
	tests/test_overlay.sh

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
