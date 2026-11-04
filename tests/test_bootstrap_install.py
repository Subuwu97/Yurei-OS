"""Early prerequisites must be installed even when their package is reused."""
import os
import subprocess
from pathlib import Path

import pytest


@pytest.mark.skipif(os.name == "nt", reason="requires the Linux build shell")
def test_cached_early_prerequisite_does_not_enable_all_core_installs(tmp_path):
    source = (Path(__file__).resolve().parents[1] / "independent/bootstrap/repo-inside.sh").read_text()
    function = source[source.index("packages() {"):source.index("\npublish() {")]
    recipes = tmp_path / "recipes"
    recipes.mkdir()
    (recipes / "ORDER").write_text("early bootstrap-install\ncore\n#> install from here on\nlate\n")
    script = r'''set -eu
srv=$1
recipes=$srv/recipes
repo=$srv/repo
stamps=$srv/stamps
jobs=1
ninja_jobs() { :; }
fingerprint() { echo test-key; }
as_user() { :; }
recipe_hash() { echo hash; }
reuse() { return 0; }
msg() { :; }
install_here() { echo "INSTALL:$1"; }
''' + function + "\npackages\n"
    result = subprocess.run(["bash", "-c", script, "test", str(tmp_path)], capture_output=True, text=True, check=True)
    assert [line for line in result.stdout.splitlines() if line.startswith("INSTALL:")] == ["INSTALL:early", "INSTALL:late"]
