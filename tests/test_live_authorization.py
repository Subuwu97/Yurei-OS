"""Exercise the actual generated live-only policy with different session subjects."""
from pathlib import Path
import shutil
import subprocess

import pytest

SOURCE = Path(__file__).resolve().parents[1] / "independent/bootstrap/iso-inside.sh"
NODE = shutil.which("node")

@pytest.mark.skipif(not NODE, reason="Node is needed to exercise the JavaScript policy")
def test_live_policy_limits_app_and_installer_authorization_to_local_active_live_user():
    text = SOURCE.read_text(encoding="utf-8")
    policy = text.split("<<'POLKIT'\n", 1)[1].split("\nPOLKIT", 1)[0]
    driver = r"""
const vm = require('node:vm');
const assert = require('node:assert/strict');
let rule;
const polkit = { Result: {YES: 'yes', NOT_HANDLED: 'default'}, addRule(fn) {rule = fn;} };
vm.runInNewContext(process.argv[1], {polkit});
const local = {user: 'live', local: true, active: true};
const action = (id, program) => ({id, lookup: () => program});
assert.equal(rule(action('org.freedesktop.Flatpak.app-install'), local), 'yes');
assert.equal(rule(action('org.freedesktop.NetworkManager.network-control'), local), 'yes');
assert.equal(rule(action('org.freedesktop.timedate1.set-timezone'), local), 'yes');
assert.equal(rule(action('org.freedesktop.policykit.exec', '/usr/bin/yurei-install'), local), 'yes');
assert.equal(rule(action('org.freedesktop.policykit.exec', '/usr/bin/bash'), local), 'default');
assert.equal(rule(action('org.freedesktop.Flatpak.override-parental-controls'), local), 'default');
for (const subject of [
  {...local, user: 'tester'}, {...local, user: 'root'},
  {...local, active: false}, {...local, local: false}
]) {
  assert.equal(rule(action('org.freedesktop.Flatpak.app-install'), subject), 'default');
  assert.equal(rule(action('org.freedesktop.NetworkManager.network-control'), subject), 'default');
  assert.equal(rule(action('org.freedesktop.policykit.exec', '/usr/bin/yurei-install'), subject), 'default');
}
"""
    result = subprocess.run([NODE, "-e", driver, policy], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stdout + result.stderr
