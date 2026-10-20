#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
OWNER="${1:?Usage: generate-cask.sh GITHUB_OWNER [REPOSITORY]}"
REPOSITORY="${2:-total-command}"
[[ "$OWNER" =~ '^[A-Za-z0-9][A-Za-z0-9-]*$' ]] || { print -u2 "Invalid GitHub owner."; exit 1; }
[[ "$REPOSITORY" =~ '^[A-Za-z0-9_.-]+$' ]] || { print -u2 "Invalid repository name."; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
DMG="dist/v$VERSION/Total-Command-$VERSION-universal.dmg"
[[ -f "$DMG" ]] || { print -u2 "First run scripts/release.sh. A notarized DMG is required."; exit 1; }
xcrun stapler validate "$DMG" > /dev/null
ZIP="dist/v$VERSION/Total-Command-$VERSION-universal.zip"
[[ -f "$ZIP" ]] || { print -u2 "The final notarized ZIP is required."; exit 1; }
(cd "dist/v$VERSION" && shasum -a 256 -c SHA256SUMS)
HASH=$(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)
mkdir -p packaging/Casks
cat > packaging/Casks/total-command.rb <<CASK
cask "total-command" do
  version "$VERSION"
  sha256 "$HASH"

  url "https://github.com/$OWNER/$REPOSITORY/releases/download/v#{version}/Total-Command-#{version}-universal.zip"
  name "Total Command"
  desc "Dual-pane file manager"
  homepage "https://github.com/$OWNER/$REPOSITORY"

  depends_on macos: :ventura

  app "TotalCommand.app"

  zap trash: "~/Library/Preferences/com.totalcommand.desktop.plist"
end
CASK
print "Generated packaging/Casks/total-command.rb from the final notarized ZIP."
