# Independent package updates

The tested desktop integration workflow publishes the independent `[yurei]`
repository to a new `repo-RUN_ID` snapshot release after all package and ISO checks pass. It does
not use the legacy CachyOS package build in `repo.yml`.

Pacman downloads `yurei.db` through `https://github.com/Subuwu97/Yurei-OS/releases/latest/download`.
Each snapshot is uploaded as a draft and marked Latest only after all files are
present. This works with GitHub immutable releases; published assets are never
replaced. Keep ISO releases as prereleases with `--latest=false`, since Latest
is the package repository pointer.

ISOs made before this change use the frozen `/releases/download/repo` URL.
They need their `/etc/pacman.d/mirrorlist` Server changed to the URL above to
receive subsequent updates. Pacman preserves edited configuration files; check
for a `.pacnew` file when updating an existing installation.

 Packages and database signatures remain enabled. Package payloads
are uploaded before the new database is exposed; the initial release stays a
draft until its files have uploaded.

## Signing identity

The PC runner keeps its GnuPG signing home at
`/home/runner/yurei-signing-gnupg`, outside the disposable build root. The build
mounts that directory privately into the chroot and uses a dedicated builder
UID. It reuses the key on subsequent builds. Neither the ISO nor the release
includes this private directory. Back it up securely before replacing the
runner; losing the key requires a deliberate signing-key transition.

The release publishes only `yurei-build.asc` and
`yurei-signing-fingerprint.txt`, along with signed packages and databases.
The publisher verifies every detached signature before uploading anything.

## Existing preview systems

Early preview ISOs used a throwaway signing identity for each build. Those
systems do not automatically trust the new persistent key. They need a
one-time public-key bootstrap with its fingerprint verified against the
published release information. The new ISO includes the correct public key
in `yurei-keyring` and needs no such bootstrap.

Do not disable pacman signature verification or import Arch/CachyOS repository
configuration. These packages belong to the independent distro.

The existing `repo.yml` is historical CachyOS packaging and must not be used
to overwrite the independent repository. Use the tested integration publisher.
