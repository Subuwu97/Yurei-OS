# Wi-Fi compared with the working CachyOS-based profile

Compared against CachyOS-Live-ISO commit
`3215497d2e8c5fea90e185affcf973dfa2cf790b`, the exact revision pinned in
Yurei's `upstream.conf`, rather than assuming today's CachyOS defaults.

| Component | CachyOS-based live image | Independent live image before this correction |
| --- | --- | --- |
| Desktop network frontend | Plasma NetworkManager integration (`plasma-nm`) | Same frontend, built from source |
| Wi-Fi backend | NetworkManager and wpa_supplicant services enabled; iwd also supplied | NetworkManager explicitly configured to use iwd |
| Desktop account | `liveuser`, UID 1000 | Passwordless root live session |
| Live wallet | `[Wallet] Enabled=false` | Upstream enabled-wallet default |

Primary reference files at that revision:

- [Live wallet settings](https://github.com/CachyOS/CachyOS-Live-ISO/blob/3215497d2e8c5fea90e185affcf973dfa2cf790b/archiso/airootfs/etc/skel/.config/kwalletrc)
- [Live account](https://github.com/CachyOS/CachyOS-Live-ISO/blob/3215497d2e8c5fea90e185affcf973dfa2cf790b/archiso/airootfs/etc/passwd)
- [Enabled supplicant service](https://github.com/CachyOS/CachyOS-Live-ISO/blob/3215497d2e8c5fea90e185affcf973dfa2cf790b/archiso/airootfs/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service)
- [Desktop package list](https://github.com/CachyOS/CachyOS-Live-ISO/blob/3215497d2e8c5fea90e185affcf973dfa2cf790b/archiso/packages_desktop.x86_64)

The reported "can't get secrets" / "awaiting authorization" messages do not
alone establish a failed driver, a bad password, or an iwd defect. Plasma's
networkmanagement KDED module supplies secrets to NetworkManager and can use
KWallet. The independent live session lacked the known-working profile's
explicit live-wallet policy.

The first correction matches that policy in the disposable live image only.
The installer removes the marked live-only file so installed users retain
normal wallet behavior. It does not change their existing personal settings.
NetworkManager remains the owner of IP configuration; iwd supplies the wireless
link, with its own IP configuration disabled.

The VM checks load the real Plasma networkmanagement module in both the live
and installed sessions and check that the installed system drops the live
wallet exception. A VM without a Wi-Fi radio cannot verify WPA authentication
against the user's access point. A physical Dell retest and NetworkManager
logs are still needed; matching the live wallet policy is not proof of a
complete hardware Wi-Fi fix. Switching the backend to wpa_supplicant would
require adding and validating that source-built package separately.
