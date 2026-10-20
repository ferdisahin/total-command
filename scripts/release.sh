#!/bin/zsh
# Creates signed, notarized universal artifacts. Does not publish anything.
set -eu
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set the name of an existing notarytool Keychain profile}"
security find-identity -v -p codesigning | awk -v wanted="$SIGNING_IDENTITY" '
  index($0, wanted) > 0 && index($0, "Developer ID Application:") > 0 { found = 1 }
  END { exit !found }
' || { print -u2 "Use a valid Developer ID Application identity name or its 40-character SHA-1 hash."; exit 1; }
[[ -f LICENSE ]] || { print -u2 "Choose a license and add LICENSE before a public release."; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 "Expected a numeric semantic version."; exit 1; }
OUT="$PWD/dist/v$VERSION"
[[ ! -e "$OUT" ]] || { print -u2 "Release output already exists: $OUT"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { print -u2 "Commit the source before building a public release."; exit 1; }
SOURCE_COMMIT=$(git rev-parse HEAD)
./test.sh
BUILD_ARCHS="arm64 x86_64" ./build.sh
codesign -dv --verbose=4 TotalCommand.app 2>&1
mkdir -p "$OUT"
print -r -- "$SOURCE_COMMIT" > "$OUT/SOURCE_COMMIT"
RELEASE_WORK=$(mktemp -d "${TMPDIR:-/tmp}/total-command-release.XXXXXX")
trap 'rm -rf "$RELEASE_WORK"' EXIT
notarize() {
  local item="$1"
  local report="$2"
  xcrun notarytool submit "$item" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$report"
  local notary_state=$(/usr/bin/plutil -extract status raw -o - "$report")
  if [[ "$notary_state" != "Accepted" ]]; then
    local submission=$(/usr/bin/plutil -extract id raw -o - "$report")
    xcrun notarytool log "$submission" --keychain-profile "$NOTARY_PROFILE" "$OUT/notary-failure.json" || true
    print -u2 "Notarization was not accepted. See $report and notary-failure.json."
    exit 1
  fi
}
/usr/bin/ditto -c -k --sequesterRsrc --keepParent TotalCommand.app "$RELEASE_WORK/submission.zip"
notarize "$RELEASE_WORK/submission.zip" "$OUT/notary-app.json"
xcrun stapler staple TotalCommand.app
xcrun stapler validate TotalCommand.app
codesign --verify --strict --verbose=1 TotalCommand.app
mkdir "$RELEASE_WORK/disk"
/usr/bin/ditto TotalCommand.app "$RELEASE_WORK/disk/TotalCommand.app"
ln -s /Applications "$RELEASE_WORK/disk/Applications"
DMG="$OUT/Total-Command-$VERSION-universal.dmg"
hdiutil create -volname "Total Command" -srcfolder "$RELEASE_WORK/disk" -format UDZO -ov "$DMG"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"
notarize "$DMG" "$OUT/notary-dmg.json"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type execute --verbose=2 TotalCommand.app
/usr/bin/ditto -c -k --sequesterRsrc --keepParent TotalCommand.app "$OUT/Total-Command-$VERSION-universal.zip"
(cd "$OUT" && shasum -a 256 *.dmg *.zip > SHA256SUMS)
print "Signed and notarized artifacts: $OUT"
print "Nothing has been uploaded to GitHub. Use scripts/publish.sh after reviewing the artifacts."
