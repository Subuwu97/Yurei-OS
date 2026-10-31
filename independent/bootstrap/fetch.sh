#!/usr/bin/env bash
# Downloads the sources listed in sources.lock into $SOURCES and checks
# their SHA-256 sums (a URL written NAME::URL is saved as NAME, as makepkg
# does). Sources not yet pinned ("-") are downloaded and their
# sums printed, then the script fails until they're filled in.
#
#   SOURCES=/path/to/cache ./fetch.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
sources=${SOURCES:?set SOURCES to the download directory}
mkdir -p "$sources"

# Places to try for a URL. ftp.gnu.org itself is often slow, so GNU files
# come from GNU's mirror redirector or kernel.org's GNU mirror first; the
# checksum check makes every mirror as good as the original.
mirrors() {
    local url=$1
    case $url in
        https://ftp.gnu.org/gnu/*)
            echo "https://ftpmirror.gnu.org/gnu/${url#https://ftp.gnu.org/gnu/}"
            echo "https://mirrors.kernel.org/gnu/${url#https://ftp.gnu.org/gnu/}"
            ;;
    esac
    echo "$url"
    # zlib.net keeps only the newest release in place and answers old
    # addresses with a web page; zlib's GitHub releases keep them all
    case $url in
        https://zlib.net/*/zlib-*.tar.gz|https://zlib.net/zlib-*.tar.gz)
            local v=${url##*/zlib-}; v=${v%.tar.gz}
            echo "https://github.com/madler/zlib/releases/download/v$v/zlib-$v.tar.gz"
            ;;
    esac
}

# download URL FILE SUM: tries each mirror until one gives a file with SUM
# (any file, while SUM is "-"); gives up on a stalled transfer (under
# 10 kB/s for a minute) instead of waiting for a timeout
download() {
    local url=$1 file=$2 sum=$3 try
    while read -r try; do
        if curl -fL --connect-timeout 30 --speed-limit 10000 --speed-time 60 \
                --retry 2 --retry-delay 5 --retry-all-errors -o "$file.part" "$try"; then
            if [[ $sum == - || $(sha256sum "$file.part" | cut -d' ' -f1) == "$sum" ]]; then
                mv "$file.part" "$file"
                return 0
            fi
            echo "  ($try gave a different file, trying the next source)" >&2
        else
            echo "  ($try didn't work, trying the next source)" >&2
        fi
    done < <(mirrors "$url")
    rm -f "$file.part"
    echo "couldn't download $url" >&2
    return 1
}

unpinned=0 missing=()
while read -r name version url sum _step; do
    [[ -z $name || $name == \#* ]] && continue
    # NAME::URL saves URL as NAME (for tarballs named only by version)
    if [[ $url == *::* ]]; then
        file=$sources/${url%%::*}
        url=${url#*::}
    else
        file=$sources/${url##*/}
    fi
    if [[ ! -f $file ]]; then
        echo "fetching $name $version"
        # keep going, so one run lists every source that can't be had
        download "$url" "$file" "$sum" || { missing+=("$name $version"); continue; }
    fi
    actual=$(sha256sum "$file" | cut -d' ' -f1)
    if [[ $sum == - ]]; then
        printf 'UNPINNED %-9s %-8s %s\n' "$name" "$version" "$actual"
        unpinned=1
    elif [[ $actual != "$sum" ]]; then
        echo "MISMATCH $name: expected $sum, got $actual" >&2
        rm -f "$file"
        exit 1
    else
        echo "ok       $name $version"
    fi
done < "$here/sources.lock"

if (( ${#missing[@]} )); then
    printf "couldn't download: %s\n" "${missing[@]}" >&2
    exit 1
fi
if (( unpinned )); then
    echo "Some sources aren't pinned yet; fill their sums into sources.lock." >&2
    [[ ${ALLOW_UNPINNED:-} == 1 ]] || exit 1
fi
