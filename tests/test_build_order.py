"""Regression checks for dependency mistakes that should fail before a build."""

import importlib.util
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[1] / "independent/packages/check_build_order.py"
spec = importlib.util.spec_from_file_location("check_build_order", SOURCE)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def tree(tmp_path, order, recipes):
    (tmp_path / "ORDER").write_text(order, encoding="utf-8")
    for name, metadata in recipes.items():
        folder = tmp_path / name
        folder.mkdir()
        (folder / "PKGBUILD").write_text(metadata, encoding="utf-8")
    return checker.validate(tmp_path)[1]


def test_split_packages_are_dependency_providers(tmp_path):
    assert not tree(tmp_path, "compiler\n#> install from here on\napp\n", {
        "compiler": "pkgname=(compiler compiler-libs)\n",
        "app": "pkgname=app\ndepends=(compiler-libs)\n",
    })


def test_post_bootstrap_forward_dependency_is_rejected(tmp_path):
    errors = tree(tmp_path, "#> install from here on\napp\nlib\n", {
        "app": "pkgname=app\ndepends=(lib)\n", "lib": "pkgname=lib\n",
    })
    assert any("must come earlier" in error for error in errors)


def test_bootstrap_forward_dependency_is_allowed(tmp_path):
    assert not tree(tmp_path, "app\nlib\n#> install from here on\n", {
        "app": "pkgname=app\ndepends=(lib)\n", "lib": "pkgname=lib\n",
    })


def test_missing_runtime_package_is_rejected(tmp_path):
    errors = tree(tmp_path, "#> install from here on\napp\n", {
        "app": "pkgname=app\ndepends=(missing)\n",
    })
    assert any("missing has no provider" in error for error in errors)


def test_bootstrap_tools_only_satisfy_build_dependencies(tmp_path):
    assert not tree(tmp_path, "#> install from here on\napp\n", {
        "app": "pkgname=app\nmakedepends=(meson ninja)\n",
    })
    (tmp_path / "app/PKGBUILD").write_text("pkgname=app\ndepends=(meson)\n")
    assert any("meson has no provider" in error for error in checker.validate(tmp_path)[1])


def test_duplicate_order_entry_is_rejected(tmp_path):
    errors = tree(tmp_path, "#> install from here on\napp\napp\n", {"app": "pkgname=app\n"})
    assert any("duplicate recipe" in error for error in errors)


def test_build_only_package_cannot_be_a_runtime_dependency(tmp_path):
    errors = tree(tmp_path, "#> install from here on\ntool build-only\napp\n", {
        "tool": "pkgname=tool\n", "app": "pkgname=app\ndepends=(tool)\n",
    })
    assert any("runtime dependency tool is build-only" in error for error in errors)


def test_versioned_and_virtual_names_resolve(tmp_path):
    assert not tree(tmp_path, "#> install from here on\nlib\napp\n", {
        "lib": "pkgname=lib\nprovides=('virtual-lib=$pkgver')\n",
        "app": "pkgname=app\ndepends=('virtual-lib>=1.0' lib)\n",
    })


def test_missing_marker_does_not_silently_disable_order_check(tmp_path):
    errors = tree(tmp_path, "app\n", {"app": "pkgname=app\n"})
    assert any("missing install marker" in error for error in errors)


def test_dynamic_package_name_fails_without_execution(tmp_path):
    errors = tree(tmp_path, "#> install from here on\napp\n", {
        "app": "pkgname=$dynamic\n",
    })
    assert any("literal package names" in error for error in errors)
