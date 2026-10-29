# Release codenames

Each Yūrei release has a **version**, the year and month it came out (like
Ubuntu: `26.10` is October 2026), and a **codename**. Yūrei means "ghost",
so the codenames come from the other spirits and creatures of Japanese
folklore, the yōkai. They go in alphabetical order, so the first letter
shows which release is newer.

Updates keep rolling between releases, as on Arch. A release is a milestone:
a tested ISO with a name. You can find the release you're on in
`/etc/os-release`, or with `fastfetch`.

| Version | Codename | The spirit |
|---|---|---|
| **26.10** | **Amabie** | A glowing mermaid-like sea spirit said to keep sickness away. The first release |
| | Bakeneko | A house cat that grows into a shape-shifting spirit |
| | Chōchin-obake | A paper lantern that comes alive, with one eye and a long tongue |
| | Daidarabotchi | A giant whose footprints became lakes and valleys |
| | Enenra | A spirit made of smoke from a bonfire |
| | Funayūrei | The ghosts of the sea: Yūrei's own family |
| | Gashadokuro | A giant skeleton that roams at night |
| | Hitodama | Floating spirit flames, like the blue flame on Yūrei's logo |
| | Inugami | A loyal dog spirit |
| | Jinmenju | A tree whose fruit have smiling faces |
| | Kitsune | A wise fox spirit that grows a new tail every hundred years |
| | Mujina | A badger that plays tricks on travellers |
| | Nekomata | A cat spirit with two tails |
| | Oni | The horned ogres of the mountains |
| | Raijū | A thunder beast that rides lightning |
| | Shōjō | Red-haired sea sprites who love to sing and drink |
| | Tanuki | A cheerful raccoon dog and master of disguise |
| | Umibōzu | A huge dark sea spirit that rises from calm water |
| | Wanyūdō | A flaming ox-cart wheel with a face |
| | Yuki-onna | The snow woman of winter storms |
| | Zashiki-warashi | A child spirit who brings good luck to the house it lives in |

There are no names for L, P, Q, V and X, which Japanese doesn't have. After
Z, the list starts again at A with new names.

## Making a release

1. Set the next version and codename in `release.conf`.
2. Update `VERSION`, `VERSION_ID`, `VERSION_CODENAME` and `PRETTY_NAME` in
   both os-release files (`pkg/yurei-settings/files/usr/lib/yurei/os-release`
   and `overlay/airootfs/etc/os-release`), and the version strings in the
   installer's `branding.desc`. `tests/test_release.sh` fails until they
   all match.
3. Mark it in the table above, then build the ISO. The ISO, the release
   page, the installer and the system all carry the version and codename.
