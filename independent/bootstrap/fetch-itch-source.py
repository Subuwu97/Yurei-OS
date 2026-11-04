#!/usr/bin/env python3
"""Fetch the pinned original Katawa Shoujo archive through its official page."""
import http.cookiejar
import json
from pathlib import Path
import re
import sys
import urllib.parse
import urllib.request

PAGE = "https://4leafstudios.itch.io/katawa-shoujo"
UPLOAD = PAGE + "/file/16033228"
MAX_BYTES = 600 * 1024 * 1024


def fetch(destination):
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    with opener.open(PAGE, timeout=30) as response:
        page = response.read(4 * 1024 * 1024).decode()
    match = re.search(r'"csrf_token":"([^"]+)"', page)
    if not match:
        match = re.search(r'name="csrf_token" value="([^"]+)"', page)
    if not match:
        raise ValueError("Official download page has no request token")
    data = urllib.parse.urlencode({"csrf_token": match[1]}).encode()
    request = urllib.request.Request(UPLOAD, data=data, headers={"Referer": PAGE})
    with opener.open(request, timeout=30) as response:
        url = json.load(response)["url"]
    if urllib.parse.urlsplit(url).scheme != "https":
        raise ValueError("Official download did not return HTTPS")
    total = 0
    with opener.open(url, timeout=30) as response, destination.open("wb") as output:
        while block := response.read(1024 * 1024):
            total += len(block)
            if total > MAX_BYTES:
                raise ValueError("Download exceeds the pinned release's size limit")
            output.write(block)
    # fetch.sh verifies the pinned SHA-256 before accepting or using this file.


if __name__ == "__main__":
    destination = Path(sys.argv[1])
    try:
        fetch(destination)
    except Exception as error:
        destination.unlink(missing_ok=True)
        # Do not print the temporary CDN URL or request token in CI logs.
        print("Official game download failed (" + type(error).__name__ + ")", file=sys.stderr)
        sys.exit(1)
