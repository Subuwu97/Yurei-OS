#!/usr/bin/env bash
# Publish only the repository from this workflow's successfully tested ISO.
# Private signing material is deliberately outside YUREI_REPO and is never read.
set -euo pipefail
repo=${YUREI_REPO:?set YUREI_REPO to the tested package repository}
: "${GH_REPO:?set GH_REPO}" "${GH_TOKEN:?set GH_TOKEN}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}"
tag=repo-$GITHUB_RUN_ID
work=$(mktemp -d /home/runner/yurei-publish.XXXXXX)
cleanup() {
    gpgconf --homedir "$work/gnupg" --kill all 2>/dev/null || true
    [[ $work == /home/runner/yurei-publish.* ]] && rm -rf "$work"
}
trap cleanup EXIT
install -d -m 0700 "$work/gnupg"
for file in yurei.db yurei.db.sig yurei.files yurei.files.sig yurei-build.asc yurei-signing-fingerprint.txt; do
    cp -L "$repo/$file" "$work/$file"
done
expected=$(tr -d '[:space:]' < "$work/yurei-signing-fingerprint.txt")
actual=$(gpg --batch --homedir "$work/gnupg" --with-colons --show-keys "$work/yurei-build.asc" 2>/dev/null | awk -F: '/^fpr/ {print $10; exit}')
[[ $expected =~ ^[A-F0-9]{40}$ && $actual == "$expected" ]]
gpg --batch --homedir "$work/gnupg" --import "$work/yurei-build.asc" >/dev/null 2>&1
for name in yurei.db yurei.files; do
    gpg --batch --homedir "$work/gnupg" --verify "$work/$name.sig" "$work/$name" >/dev/null 2>&1
done
shopt -s nullglob
packages=("$repo"/*.pkg.tar.zst)
(( ${#packages[@]} > 0 )) || { echo "No tested packages" >&2; exit 1; }
assets=()
for package in "${packages[@]}"; do
    [[ -s $package.sig ]]
    (( $(stat -c %s "$package") < 2147483648 )) || { echo "Package exceeds GitHub asset limit: ${package##*/}" >&2; exit 1; }
    gpg --batch --homedir "$work/gnupg" --verify "$package.sig" "$package" >/dev/null 2>&1
    assets+=("$package" "$package.sig")
done
printf 'Verified %d package signatures and the signed repository databases.\n' "${#packages[@]}"
python3 - "$work" "$GITHUB_SHA" "$GITHUB_RUN_ID" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1], 'repository-build.json').write_text(json.dumps({
    'kind': 'Yurei independent packages; not Arch or CachyOS packages',
    'source_commit': sys.argv[2], 'tested_iso_build': sys.argv[3],
}, indent=2) + '\n')
PY
cat > "$work/README-repository.txt" <<NOTES
Yurei independent signed package repository

Only published after the package checks, ISO boots and installation tests pass.
Tested build: https://github.com/$GH_REPO/actions/runs/$GITHUB_RUN_ID
Source: $GITHUB_SHA
Signing key fingerprint: $expected

The private key remains on the build runner. This release contains only its
public key, signed packages and signed repository databases.

Older test ISOs used temporary signing keys. They need a one-time import of
this public key after independently checking the fingerprint above. New ISOs
built with this persistent identity already trust it. Never disable signature
checking to work around a key error, and never mix Arch/CachyOS packages here.

Public key: https://github.com/$GH_REPO/releases/download/$tag/yurei-build.asc
Snapshot URL: https://github.com/$GH_REPO/releases/download/$tag
Update URL: https://github.com/$GH_REPO/releases/latest/download
NOTES
cd "$work"
# Checksums cover public release data only; no signing-home glob is used.
: > SHA256SUMS
for asset in "${assets[@]}" "$work"/yurei.* "$work/yurei-build.asc" "$work/yurei-signing-fingerprint.txt" "$work/repository-build.json"; do
    printf '%s  %s\n' "$(sha256sum "$asset" | cut -d ' ' -f1)" "${asset##*/}" >> SHA256SUMS
done
# Published releases may be immutable. Never replace their assets. A rerun
# of a completed snapshot only verifies it; failed drafts can resume safely.
if [[ $(gh release view "$tag" --repo "$GH_REPO" --json isDraft --jq .isDraft 2>/dev/null || true) == false ]]; then
    curl --fail --location --retry 5 --retry-all-errors "https://github.com/$GH_REPO/releases/download/$tag/yurei.db" -o public-yurei.db
    cmp yurei.db public-yurei.db
    echo "Verified existing immutable snapshot $tag"
    exit 0
fi
if ! gh release view "$tag" --repo "$GH_REPO" >/dev/null 2>&1; then
    gh release create "$tag" --repo "$GH_REPO" --target "$GITHUB_SHA" --draft --latest=false \
        --title "Yurei package repository snapshot $GITHUB_RUN_ID" --notes-file README-repository.txt
fi
# Payloads first, in a new draft snapshot. The latest pointer changes only
# after every upload succeeds. Published snapshots are never modified.
gh release upload "$tag" "${assets[@]}" --repo "$GH_REPO" --clobber
gh release upload "$tag" yurei-build.asc yurei-signing-fingerprint.txt repository-build.json SHA256SUMS README-repository.txt --repo "$GH_REPO" --clobber
gh release upload "$tag" yurei.db yurei.db.sig yurei.files yurei.files.sig --repo "$GH_REPO" --clobber
gh release edit "$tag" --repo "$GH_REPO" --draft=false --latest --notes-file README-repository.txt
# Check the public URL that pacman actually requests, not just the API upload.
curl --fail --location --retry 5 --retry-all-errors \
    "https://github.com/$GH_REPO/releases/latest/download/yurei.db" -o public-yurei.db
cmp yurei.db public-yurei.db
printf 'Published signed yurei.db and %d packages. Fingerprint: %s\n' "${#packages[@]}" "$expected"
