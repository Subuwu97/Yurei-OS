# Independent package updates

The tested desktop integration workflow publishes the independent `[yurei]`
repository to the `repo` release after all package and ISO checks pass. It does
not use the legacy CachyOS package build in `repo.yml`.

Pacman downloads `yurei.db` from the URL already shipped in the independent
mirror list. Packages and database signatures remain enabled. Package payloads
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
