"""The special official-game downloader accepts only HTTPS and bounded data."""
import importlib.util
import io
import json
from pathlib import Path
import pytest

SOURCE = Path(__file__).resolve().parents[1] / "independent/bootstrap/fetch-itch-source.py"
spec = importlib.util.spec_from_file_location("itch_source", SOURCE)
fetcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetcher)

class Opener:
    def __init__(self, url="https://cdn.example.invalid/archive", payload=b"pinned archive"):
        self.url, self.payload = url, payload
        self.calls = []
    def open(self, request, **kwargs):
        self.calls.append(request)
        if len(self.calls) == 1:
            return io.BytesIO(b'{"csrf_token":"public-request-token"}')
        if len(self.calls) == 2:
            assert request.full_url == fetcher.UPLOAD
            assert request.get_method() == "POST"
            return io.BytesIO(json.dumps({"url": self.url}).encode())
        return io.BytesIO(self.payload)

def test_download_uses_official_post_then_https(tmp_path, monkeypatch):
    opener = Opener()
    monkeypatch.setattr(fetcher.urllib.request, "build_opener", lambda *a: opener)
    path = tmp_path / "game.part"
    fetcher.fetch(path)
    assert path.read_bytes() == b"pinned archive"
    assert opener.calls[0] == fetcher.PAGE

@pytest.mark.parametrize("url", ["file:///etc/passwd", "http://cdn.example.invalid/game"])
def test_refuses_non_https_download(tmp_path, monkeypatch, url):
    monkeypatch.setattr(fetcher.urllib.request, "build_opener", lambda *a: Opener(url))
    with pytest.raises(ValueError, match="HTTPS"):
        fetcher.fetch(tmp_path / "game.part")

def test_download_size_is_bounded(tmp_path, monkeypatch):
    monkeypatch.setattr(fetcher.urllib.request, "build_opener", lambda *a: Opener(payload=b"too big"))
    monkeypatch.setattr(fetcher, "MAX_BYTES", 2)
    with pytest.raises(ValueError, match="size limit"):
        fetcher.fetch(tmp_path / "game.part")
