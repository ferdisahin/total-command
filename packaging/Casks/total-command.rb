cask "total-command" do
  version "0.2.4"
  sha256 "a0e2f4866c46cdd669882d545b08f0af8e5053643c1724cad6f6702d347c65e1"

  url "https://github.com/ferdisahin/total-command/releases/download/v#{version}/Total-Command-#{version}-universal.zip"
  name "Total Command"
  desc "Dual-pane file manager"
  homepage "https://github.com/ferdisahin/total-command"

  depends_on macos: :ventura

  app "TotalCommand.app"

  zap trash: "~/Library/Preferences/com.totalcommand.desktop.plist"
end
