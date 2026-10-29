#!/usr/bin/env bash
# Downloads the sources listed in sources.lock into $SOURCES and checks
# their SHA-256 sums. Sources not yet pinned ("-") are downloaded and their
# sums printed, then the script fails until they're filled in.
#
#   SOURCES=/path/to/cache ./fetch.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
sources=${SOURCES:?set SOURCES to the download directory}
mkdir -p "$sources"

unpinned=0
while read -r name version url sum; do
    [[ -z $name || $name == \#* ]] && continue
    file=$sources/${url##*/}
    if [[ ! -f $file ]]; then
        echo "fetching $name $version"
        curl -fL --retry 4 --retry-delay 5 -o "$file.part" "$url"
        mv "$file.part" "$file"
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

if (( unpinned )); then
    echo "Some sources aren't pinned yet; fill their sums into sources.lock." >&2
    [[ ${ALLOW_UNPINNED:-} == 1 ]] || exit 1
fi
