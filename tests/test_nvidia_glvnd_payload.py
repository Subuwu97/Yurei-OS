"""Package synthetic NVIDIA input with the real recipe; never load a driver."""

import os
from pathlib import Path
import subprocess
import sys

import pytest


@pytest.mark.skipif(sys.platform != 'linux', reason='recipe requires Linux Bash/install')
def test_nvidia_leaves_dispatch_loaders_to_libglvnd(tmp_path):
    recipe = Path(__file__).resolve().parents[1] / 'independent/packages/nvidia-utils/PKGBUILD'
    # The installer payload is synthetic. Only ldconfig is stubbed because
    # these are text fixtures, not ELF libraries; no proprietary code executes.
    source = tmp_path / 'NVIDIA-Linux-x86_64-595.112.07'
    source.mkdir()
    loaders = ['libEGL.so.1', 'libGL.so.1', 'libGLESv1_CM.so.1',
               'libGLESv2.so.2', 'libGLX.so.0', 'libGLdispatch.so.0', 'libOpenGL.so.0']
    vendors = ['libEGL_nvidia.so.1', 'libGLX_nvidia.so.1',
               'libnvidia-glcore.so.595.112.07', 'libnvidia-allocator.so.1']
    for name in loaders + vendors + ['nvidia-smi', 'nvidia-modprobe', 'LICENSE', 'nvidia_icd.json']:
        (source / name).write_text('fixture\n')
    (source / 'firmware').mkdir()
    (source / 'firmware/gsp.bin').write_text('fixture\n')
    commands = tmp_path / 'commands'
    commands.mkdir()
    (commands / 'ldconfig').write_text('#!/bin/sh\nexit 0\n')
    (commands / 'ldconfig').chmod(0o755)
    package = tmp_path / 'package'
    subprocess.run(['bash', '-eu', '-c', 'source "$1"; package', 'test', str(recipe)],
                   cwd=tmp_path, check=True,
                   env={**os.environ, 'PATH': f'{commands}:{os.environ["PATH"]}', 'pkgdir': str(package)})
    lib = package / 'usr/lib'
    for name in loaders:
        assert not (lib / name).exists(), name
        assert not (lib / name.split('.so.')[0]).with_suffix('.so').is_symlink(), name
    for name in vendors:
        assert (lib / name).is_file(), name
    assert (lib / 'gbm/nvidia-drm_gbm.so').is_symlink()
