# Checking package dependencies before a build

Run `python3 independent/packages/check_build_order.py` from the repository.
It also runs with `make test` and the source/recipe checks before bootstrap.

The checker reads literal top-level `pkgname`, `provides`, `depends` and
`makedepends` declarations without executing PKGBUILDs. It resolves split
package outputs and virtual names, detects missing providers and duplicate
ORDER entries, and prevents runtime dependencies on build-only recipes.

After `#> install from here on`, each dependency's recipe must occur earlier
in ORDER (or be an output of the same recipe). Earlier recipes use the
pre-existing bootstrap chroot, so forward ordering is allowed for that section.
Missing providers are still reported. Meson and Ninja are explicit build-only
exceptions: `base2-inside.sh` already builds them from pinned sources. They do
not satisfy an unpackaged runtime dependency.

This is an early consistency check, not a dependency resolver. It does not
verify version constraints, dependencies declared inside package functions,
undeclared library dependencies, or libraries actually used by the binaries.
Keep the installed-root checks and real builds as the authority for those.
New dynamic top-level metadata needs explicit support; it should not silently
bypass the check.
