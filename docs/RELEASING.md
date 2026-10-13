# Releasing

## One command

```bash
scripts/ship.sh 0.2.0
```

Builds, notarizes, signs the appcast, commits, tags, pushes, creates the GitHub Release,
uploads the assets, publishes the appcast, and verifies that the live feed serves the new
build before it says DONE.

**It is safe to re-run.** Every step checks whether it is already done. If the run dies
halfway (a failed push, a notarization timeout, Ctrl-C), fix the cause and run the *same*
command again. That is the resume path; there is no separate flag.

Add `--rebuild` to force a rebuild of a version that is already packaged.

`scripts/release.sh <version>` is the build half on its own: everything up to the
artifacts in `dist/`, nothing pushed. `NOTARIZE=0 scripts/release.sh <version>` skips
Apple for a local test; never publish that build.

## First-time setup

### Once per project

```bash
scripts/setup-repos.sh
```

Creates `jorgeMartinez293/neowall` (this code) and `jorgeMartinez293/neowall-releases`
(downloads, plus the appcast on a `gh-pages` branch with Pages enabled), and pushes `main`.
Both are public; `SOURCE_VISIBILITY=private` keeps the source closed.

### Once per machine

These are shared with the sibling apps, so a Mac that already ships one of them has all
of it.

1. **Sparkle key.** The private EdDSA key lives in the login Keychain, in the item
   `https://sparkle-project.org`. Its public half is `SUPublicEDKey` in
   `Resources/Info.plist`. On a new Mac, restore the Keychain item from a backup; see
   [DISTRIBUTION.md](DISTRIBUTION.md#the-key) for why generating a new one is not an option.
2. **Developer ID.** A "Developer ID Application" certificate in the login keychain:
   `security find-identity -v -p codesigning`.
3. **notarytool profile.**
   `xcrun notarytool store-credentials vaho-notary --apple-id <apple-id> --team-id <team-id>`.
   It uses an app-specific password, stored in the Keychain. Never in a file in this repo.
4. **GitHub.** `gh auth login`.
5. **create-dmg.** `brew install create-dmg`. It drives Finder to lay the disk image's
   window out, so it needs a logged-in GUI session and cannot run headless.

## Things that will bite

- **A dark-wake Mac cannot sign the appcast.** Reading the private key needs a Keychain
  prompt, which needs a real GUI session. Sparkle reports the failure as "Private key not
  found — run the generate_keys tool". Do **not** do that; it orphans every install. Wake
  the Mac and re-run.
- **Releases ship from `main`.** `ship.sh` refuses any other branch (`ALLOW_ANY_BRANCH=1`
  to override deliberately). Every installed user updates to whatever that run publishes.
- **Old zips in `dist/` are load-bearing.** They are what deltas are computed from.
- **`CFBundleVersion` is bumped by `release.sh`, never by hand.** It is what Sparkle
  compares, and it must only ever go up.
