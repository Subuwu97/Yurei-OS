"""Test preinstalled-game launch preparation using synthetic files only."""

import importlib.util
import json
from pathlib import Path

import pytest


SOURCE = Path(__file__).resolve().parents[1] / "independent/packages/yurei-game-launcher/yurei-game.py"
spec = importlib.util.spec_from_file_location("yurei_game", SOURCE)
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


@pytest.fixture
def game(tmp_path):
    seed = tmp_path / "seed"
    payload = seed / "ddlc/payload"
    payload.mkdir(parents=True)
    (payload / "start.sh").write_text("#!/bin/sh\nexit 0\n")
    (payload / "character.dat").write_text("synthetic fixture")
    manifest = seed / "ddlc.json"
    manifest.write_text(json.dumps({"version": "1", "entrypoint": "start.sh"}))
    return seed, tmp_path / "user-data", manifest


def test_first_launch_copies_complete_payload(game):
    seed, data, _ = game
    entry = launcher.prepare_game(seed, data, "ddlc")
    assert entry == data / "ddlc/payload/start.sh"
    assert entry.read_text() == (seed / "ddlc/payload/start.sh").read_text()
    assert (data / "ddlc/payload/character.dat").read_text() == "synthetic fixture"


def test_later_launch_preserves_game_file_deletions_and_saves(game):
    seed, data, _ = game
    entry = launcher.prepare_game(seed, data, "ddlc")
    (entry.parent / "character.dat").unlink()
    (entry.parent / "save.dat").write_text("my progress")
    launcher.prepare_game(seed, data, "ddlc")
    assert not (entry.parent / "character.dat").exists()
    assert (entry.parent / "save.dat").read_text() == "my progress"
    assert (seed / "ddlc/payload/character.dat").is_file()


def test_two_users_have_independent_game_trees(game):
    seed, data, _ = game
    first = launcher.prepare_game(seed, data / "one", "ddlc")
    second = launcher.prepare_game(seed, data / "two", "ddlc")
    (first.parent / "character.dat").unlink()
    assert (second.parent / "character.dat").is_file()


def test_update_never_silently_resets_a_playthrough(game):
    seed, data, manifest = game
    entry = launcher.prepare_game(seed, data, "ddlc")
    (entry.parent / "save.dat").write_text("my progress")
    manifest.write_text(json.dumps({"version": "2", "entrypoint": "start.sh"}))
    with pytest.raises(ValueError, match="migration"):
        launcher.prepare_game(seed, data, "ddlc")
    assert (entry.parent / "save.dat").read_text() == "my progress"


def test_unverified_entrypoint_cannot_launch(game):
    seed, data, manifest = game
    manifest.write_text(json.dumps({"version": "1", "entrypoint": None}))
    with pytest.raises(ValueError, match="verified entrypoint"):
        launcher.prepare_game(seed, data, "ddlc")
    assert not (data / "ddlc").exists()


def test_entrypoint_cannot_escape_payload(game):
    seed, data, manifest = game
    manifest.write_text(json.dumps({"version": "1", "entrypoint": "../outside.sh"}))
    with pytest.raises(ValueError, match="inside the game directory"):
        launcher.prepare_game(seed, data, "ddlc")


def test_failed_copy_does_not_publish_partial_install(game, monkeypatch):
    seed, data, _ = game

    def fail(*args, **kwargs):
        raise OSError("simulated out of space")

    monkeypatch.setattr(launcher.shutil, "copytree", fail)
    with pytest.raises(OSError, match="out of space"):
        launcher.prepare_game(seed, data, "ddlc")
    assert not (data / "ddlc").exists()
    assert not list(data.iterdir())
