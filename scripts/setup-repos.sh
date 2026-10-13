#!/usr/bin/env bash
# One-time setup: create the two GitHub repos a release is published to.
#
# Usage: scripts/setup-repos.sh
#
#   jorgeMartinez293/neowall            the source; `origin` of this checkout.
#   jorgeMartinez293/neowall-releases   release assets, plus the Sparkle appcast on a
#                                       gh-pages branch served by GitHub Pages (SUFeedURL).
#
# Both are created PUBLIC, like the sibling apps. The releases repo has to be: the app
# downloads its updates from it without credentials. Set SOURCE_VISIBILITY=private to keep
# the source closed.
#
# Safe to re-run: every step checks whether it is already done.
set -euo pipefail
cd "$(dirname "$0")/.."

OWNER="jorgeMartinez293"
SOURCE_REPO="$OWNER/neowall"
RELEASE_REPO="$OWNER/neowall-releases"
SOURCE_VISIBILITY="${SOURCE_VISIBILITY:-public}"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
skip() { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }

gh auth status >/dev/null 2>&1 || { echo "ERROR: run 'gh auth login' first." >&2; exit 1; }

# ── Source repo ───────────────────────────────────────────────────────────────
say "Source repo ($SOURCE_REPO, $SOURCE_VISIBILITY)"
[ -d .git ] || git init -q -b main
if ! git rev-parse -q --verify HEAD >/dev/null; then
  git add -A
  git commit -q -m "Initial commit"
  echo "  created the initial commit"
fi
if ! gh repo view "$SOURCE_REPO" >/dev/null 2>&1; then
  gh repo create "$SOURCE_REPO" "--$SOURCE_VISIBILITY" \
    --description "An animated ASCII wallpaper for macOS that costs almost nothing"
  echo "  created $SOURCE_REPO"
else
  skip "$SOURCE_REPO exists"
fi
if git remote get-url origin >/dev/null 2>&1; then
  skip "origin is $(git remote get-url origin)"
else
  git remote add origin "https://github.com/$SOURCE_REPO.git"
fi
git push -q -u origin main
skip "main pushed"

# ── Releases repo ─────────────────────────────────────────────────────────────
say "Releases repo ($RELEASE_REPO, public)"
if ! gh repo view "$RELEASE_REPO" >/dev/null 2>&1; then
  gh repo create "$RELEASE_REPO" --public --description "neowall downloads and update feed"
  echo "  created $RELEASE_REPO"
else
  skip "$RELEASE_REPO exists"
fi

# scripts/ship.sh checks out both branches and copies the appcast over, so each has to
# exist with an appcast.xml in it. An empty feed is a valid one: no updates.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
EMAIL=$(git config user.email); NAME=$(git config user.name)
gh repo clone "$RELEASE_REPO" "$WORK" -- -q 2>/dev/null
cd "$WORK"
git config user.email "$EMAIL"; git config user.name "$NAME"
for BR in main gh-pages; do
  if git ls-remote --exit-code --heads origin "$BR" >/dev/null 2>&1; then
    skip "branch $BR exists"
    continue
  fi
  # The last form is for a clone with no commits yet, where there is nothing to branch from.
  git checkout -q "$BR" 2>/dev/null || git checkout -q -b "$BR" 2>/dev/null \
    || git symbolic-ref HEAD "refs/heads/$BR"
  if [ ! -f appcast.xml ]; then
    cat > appcast.xml <<'XML'
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>neowall</title>
    </channel>
</rss>
XML
    printf '# neowall-releases\n\nDownloads and the update feed of [neowall](https://github.com/%s).\n' "$SOURCE_REPO" > README.md
    git add appcast.xml README.md
    git commit -q -m "Empty appcast"
  fi
  git push -q -u origin "$BR"
  echo "  created branch $BR"
done
cd - >/dev/null

# ── GitHub Pages ──────────────────────────────────────────────────────────────
say "GitHub Pages on gh-pages"
if gh api "repos/$RELEASE_REPO/pages" >/dev/null 2>&1; then
  skip "already enabled"
else
  gh api -X POST "repos/$RELEASE_REPO/pages" -f 'source[branch]=gh-pages' -f 'source[path]=/' >/dev/null
  echo "  enabled"
fi

FEED=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" Resources/Info.plist)
say "Done. The feed will be served at $FEED"
echo "Publish the first release with: scripts/ship.sh <version>"
