cask "total-command" do
  version "0.2.2"
  sha256 "5244a6dff502deece7064a206fbb56538a0a216311d8338c7eafe2bd85ffae99"

  url "https://github.com/ferdisahin/total-command/releases/download/v#{version}/Total-Command-#{version}-universal.zip"
  name "Total Command"
  desc "Dual-pane file manager"
  homepage "https://github.com/ferdisahin/total-command"

  depends_on macos: :ventura

  app "TotalCommand.app"

  zap trash: "~/Library/Preferences/com.totalcommand.desktop.plist"
end
