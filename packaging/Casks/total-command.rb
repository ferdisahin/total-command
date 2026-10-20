cask "total-command" do
  version "0.2.1"
  sha256 "20a34bd63a535cff85811a1803e77a594728c6e0d362c9d4730725c549d47d0a"

  url "https://github.com/ferdisahin/total-command/releases/download/v#{version}/Total-Command-#{version}-universal.zip"
  name "Total Command"
  desc "Dual-pane file manager"
  homepage "https://github.com/ferdisahin/total-command"

  depends_on macos: :ventura

  app "TotalCommand.app"

  zap trash: "~/Library/Preferences/com.totalcommand.desktop.plist"
end
