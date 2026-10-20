#!/bin/zsh
# Publishes the already notarized artifacts as a draft prerelease for review.
set -eu
cd "$(dirname "$0")/.."
REPOSITORY="${1:?Usage: publish.sh OWNER/total-command}"
[[ "$REPOSITORY" =~ '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$' ]] || { print -u2 "Invalid repository."; exit 1; }
[[ -f LICENSE ]] || { print -u2 "LICENSE is required."; exit 1; }
command -v gh >/dev/null || { print -u2 "GitHub CLI (gh) is required."; exit 1; }
gh auth status
[[ -z "$(git status --porcelain)" ]] || { print -u2 "Commit the release source before publishing."; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
TAG="v$VERSION"
OUT="dist/$TAG"
DMG="$OUT/Total-Command-$VERSION-universal.dmg"
ZIP="$OUT/Total-Command-$VERSION-universal.zip"
[[ -f "$DMG" && -f "$ZIP" && -f "$OUT/SHA256SUMS" ]] || { print -u2 "Missing signed release artifacts."; exit 1; }
[[ -f "$OUT/SOURCE_COMMIT" ]] || { print -u2 "Missing source commit manifest."; exit 1; }
SOURCE_COMMIT=$(cat "$OUT/SOURCE_COMMIT")
[[ "$SOURCE_COMMIT" == "$(git rev-parse HEAD)" ]] || { print -u2 "Artifacts do not match the current source commit."; exit 1; }
REMOTE_COMMIT=$(gh api "repos/$REPOSITORY/commits/$TAG" --jq .sha)
[[ "$SOURCE_COMMIT" == "$REMOTE_COMMIT" ]] || { print -u2 "Remote release tag does not match the signed source."; exit 1; }
xcrun stapler validate "$DMG"
(cd "$OUT" && shasum -a 256 -c SHA256SUMS)
# --verify-tag prevents accidentally associating artifacts with the wrong source.
gh release create "$TAG" "$DMG" "$ZIP" "$OUT/SHA256SUMS" "$OUT/SOURCE_COMMIT" --repo "$REPOSITORY" \
  --verify-tag --draft --prerelease --title "Total Command $VERSION" --generate-notes
print "Draft prerelease created; review it on GitHub before making it public."
