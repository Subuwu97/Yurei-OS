# Yūrei independent build (experiment)

The build system for a Yūrei that doesn't sit on another distribution. See
[docs/INDEPENDENT.md](../docs/INDEPENDENT.md) for what that means, what it
takes, and the plan.

## Stage 1: the cross toolchain

`bootstrap/` builds binutils, GCC, the Linux API headers, glibc and libstdc++
from upstream source, for the target `x86_64-yurei-linux-gnu`. It runs on any
Linux host with a C compiler (plus bison, gawk, texinfo and m4), as an
ordinary user:

```sh
export YUREI=$HOME/yurei-root SOURCES=$HOME/yurei-sources
bootstrap/fetch.sh     # downloads and checks the tarballs in sources.lock
bootstrap/stage1.sh    # about an hour on 2 cores; or name steps, e.g. stage1.sh glibc_build check
```

It ends by compiling a C and a C++ program with the new toolchain, and
running them on Yūrei's own glibc. GitHub Actions runs the same steps
(`.github/workflows/bootstrap.yml`) whenever this directory changes.

**Pinning sources.** `sources.lock` lists each tarball's SHA-256. New entries
start as `-`. The first CI run prints their sums, which get checked against
upstream's signatures and filled in. From then on, a changed tarball stops
the build.
