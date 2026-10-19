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
HASH=$(shasum -a 256 "$DMG" | cut -d ' ' -f 1)
mkdir -p packaging/Casks
cat > packaging/Casks/total-command.rb <<CASK
cask "total-command" do
  version "$VERSION"
  sha256 "$HASH"

  url "https://github.com/$OWNER/$REPOSITORY/releases/download/v#{version}/Total-Command-#{version}-universal.dmg"
  name "Total Command"
  desc "Dual-pane file manager for macOS"
  homepage "https://github.com/$OWNER/$REPOSITORY"

  depends_on macos: ">= :ventura"

  app "TotalCommand.app"

  zap trash: "~/Library/Preferences/com.totalcommand.desktop.plist"
end
CASK
print "Generated packaging/Casks/total-command.rb from the final notarized DMG."
