# Distribution

How a build gets from this repo onto someone's Mac, and how it updates afterwards.

## The shape of it

```
  jorgeMartinez293/neowall            source. tagged v<version> per release.
  jorgeMartinez293/neowall-releases   everything users download:
    ├─ Releases/v<version>/           neowall-<version>.zip, neowall.dmg, neowall<n>-<m>.delta
    ├─ gh-pages/appcast.xml           the Sparkle feed (SUFeedURL points here)
    └─ main/appcast.xml               same file, so the feed is diffable in the repo view
```

Two repos on purpose. Release assets and the appcast are pushed on every release; keeping
them apart means a bad upload never needs a force-push over the code.

## First download

The stable link for a website or the README:

```
https://github.com/jorgeMartinez293/neowall-releases/releases/latest/download/neowall.dmg
```

GitHub resolves `latest` at request time, so the link never changes. That works only
because **every** release uploads an asset named exactly `neowall.dmg`.

The disk image is signed with a Developer ID identity, notarized, and stapled:

- **signed** — Gatekeeper will not open an unsigned or ad-hoc app from a download at all.
- **notarized** — without the ticket the user gets "Apple could not verify…" and has to
  right-click → Open, which most people read as "this app is broken".
- **stapled** — the ticket is attached to the file on disk, so a first launch works
  offline.

The `.app` inside is notarized and stapled separately from the `.dmg`, because the disk
image is its own downloaded file and Gatekeeper checks it on mount.

The binary is universal (Apple Silicon and Intel), so there is one download.

## Updates

[Sparkle](https://sparkle-project.org), configured from `Resources/Info.plist`:

| Key | What it does |
|---|---|
| `SUFeedURL` | `https://jorgeMartinez293.github.io/neowall-releases/appcast.xml` |
| `SUPublicEDKey` | EdDSA public key. Every download is verified against it before install. |
| `SUEnableAutomaticChecks` | Checks are on from the first launch, without asking. |
| `SUScheduledCheckInterval` | 86400 — once a day. |

`Updater.shared` (`Sources/neowall/Updater.swift`) starts it. The `auto_update` config key
turns the daily check off; "Check for Updates…" in the menu bar icon runs one by hand.

The daily check is one timer and one small HTTP request. Nothing of Sparkle runs between
checks, and its helper processes exist only while an update is being installed.

`generate_appcast` also produces **delta** files (`neowall<new>-<old>.delta`) so an
existing install downloads only what changed. Deltas are computed from the previous
`.zip`s, which is why:

> **`dist/` keeps every past `.zip`. Do not delete them.**

Without an old zip on disk, that version's users fall back to the full download.

### The key

The private EdDSA key lives in the login Keychain and nowhere else, and it is **shared
with the sibling apps** (vaho, bruma, vidrio, sider): they all carry the same
`SUPublicEDKey`. Losing it does **not** mean "generate a new pair": every installed copy
trusts only the public key baked into its own `Info.plist`, so a new pair means every
existing user of every one of those apps stops receiving updates and has to reinstall by
hand. Back up the Keychain item.

`scripts/release.sh` refuses to run if `SUPublicEDKey` is empty, for the mirror reason: a
build shipped with a blank key can never be updated.

## Version numbers

- `CFBundleShortVersionString` — what people see (`0.2.0`).
- `CFBundleVersion` — a plain increasing integer. **This is what Sparkle compares.** It
  must never go backwards or repeat, which is why `scripts/release.sh` bumps it rather
  than anyone typing it.

## Signing during development

`make app` signs with the Developer ID certificate when the keychain has one, then Apple
Development, then ad-hoc. neowall holds no privacy permissions, so an ad-hoc build works;
only `make notarize-app` and `make notarize-dmg` insist on the Developer ID.
