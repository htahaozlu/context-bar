cask "context-bar" do
  version "0.7.1"
  sha256 "9321fa860ddffbddd08eba9c61c45544e57111c8147c0d1557f0898385c9931f"

  url "https://github.com/htahaozlu/context-bar/releases/download/v#{version}/ContextBar.dmg"
  name "ContextBar"
  desc "Usage and cost visibility for Claude Code and Codex — menubar app and CLI"
  homepage "https://github.com/htahaozlu/context-bar"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on macos: :ventura

  app "ContextBar.app"

  zap trash: [
    "~/.context-bar",
    "~/Library/Preferences/com.htahaozlu.contextbar.plist",
    "~/Library/Saved Application State/com.htahaozlu.contextbar.savedState",
  ]
end
