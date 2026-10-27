# The `[yurei]` package repository

Installed Yūrei systems receive updates to `yurei-settings` and `yurei-gaming`
from a signed pacman repository. It is published as assets of the `repo`
GitHub release by `.github/workflows/repo.yml`.

## One-time setup

1. **Create a signing key**. Do this on your own machine, not in CI:

   ```sh
   gpg --quick-gen-key "Yūrei Linux packages <packages@yurei.invalid>" ed25519 sign never
   ```

   CI signs without a prompt, so press Enter at the passphrase prompt to
   leave it empty. Keep a backup of the key somewhere safe.

2. **Add the private key to GitHub**. Go to *Settings → Secrets and variables
   → Actions → New repository secret*, name it `YUREI_SIGNING_KEY`, and paste
   the output of:

   ```sh
   gpg --armor --export-secret-keys "Yūrei Linux packages"
   ```

3. **Commit the public key** as `keys/yurei.asc`:

   ```sh
   gpg --armor --export "Yūrei Linux packages" > keys/yurei.asc
   ```

4. **Publish**. Run *Actions → Publish package repository → Run workflow*. It
   also runs on its own whenever `pkg/` changes on `main`.

## What changes once `keys/yurei.asc` exists

`build.sh` puts the public key on the ISO. During installation,
`yurei-install-target` trusts it with `pacman-key` and adds the following to
the new system's `/etc/pacman.conf`:

```ini
[yurei]
SigLevel = Required DatabaseRequired
Server = https://github.com/subuwu97/Y-rei-Linux/releases/download/repo
```

Until the key exists, ISOs install the Yūrei packages from the ISO itself
and nothing else changes.

## Releasing an update

Bump `pkgver` (or `pkgrel`) in `pkg/yurei-settings/PKGBUILD` and merge to
`main`. Users get the update with their next `yurei update`.
